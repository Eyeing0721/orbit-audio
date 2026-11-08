"""Opt-in loopback HTTP API, bounded serial jobs, no third-party web framework."""
from __future__ import annotations

import collections
import hmac
import json
import os
import secrets
import shutil
import signal
import subprocess
import sys
import threading
import tempfile
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from automation import ACTIONS, LONG_ACTIONS, execute
from project_io import VERSION, OrbitError, Paths, number, read_json

BODY_LIMIT = 1024 * 1024
TERMINAL = {"succeeded", "failed", "cancelled"}


def kill_tree(process):
    if process and process.poll() is None:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        else:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


class Jobs:
    def __init__(self, workspace, max_render_seconds=600):
        self.workspace = str(Path(workspace).resolve())
        self.max_render_seconds = max_render_seconds
        self.condition = threading.Condition()
        self.records, self.queue = collections.OrderedDict(), collections.deque()
        self.closed = False
        self.thread = threading.Thread(target=self._work, name="orbit-api-jobs", daemon=True)
        self.thread.start()

    @staticmethod
    def public(job):
        return {k: v for k, v in job.items() if not k.startswith("_")}

    def submit(self, request):
        if not isinstance(request, dict) or request.get("action") not in LONG_ACTIONS:
            raise OrbitError(f"Job action must be one of: {', '.join(LONG_ACTIONS)}")
        with self.condition:
            if self.closed:
                raise OrbitError("Service is closing", "unavailable", 503)
            if sum(j["state"] not in TERMINAL for j in self.records.values()) >= 16:
                raise OrbitError("Job queue is full (16 pending/running)", "queue_full", 429)
            # Retain only bounded history; no audio or credentials in job logs.
            for key in list(self.records):
                if len(self.records) < 128:
                    break
                if self.records[key]["state"] in TERMINAL:
                    del self.records[key]
            job = dict(id=uuid.uuid4().hex, action=request["action"], state="queued", progress=0,
                       message="Queued", createdAt=time.time(), _request=request, _process=None)
            self.records[job["id"]] = job
            self.queue.append(job["id"])
            self.condition.notify()
            return self.public(job)

    def get(self, job_id=None):
        with self.condition:
            if job_id is None:
                return [self.public(j) for j in self.records.values()]
            if job_id not in self.records:
                raise OrbitError("Job not found", "not_found", 404)
            return self.public(self.records[job_id])

    def cancel(self, job_id):
        with self.condition:
            if job_id not in self.records:
                raise OrbitError("Job not found", "not_found", 404)
            job = self.records[job_id]
            if job["state"] in TERMINAL:
                return self.public(job)
            if job["state"] == "queued":
                self.queue.remove(job_id)
                job.pop("_request", None)
                job.update(state="cancelled", message="Cancelled", finishedAt=time.time())
                return self.public(job)
            job.update(state="cancelling", message="Stopping worker process tree")
            process = job["_process"]
        kill_tree(process)
        with self.condition:
            job.update(state="cancelled", message="Cancelled", finishedAt=time.time())
            return self.public(job)

    def close(self):
        with self.condition:
            self.closed = True
            ids = [key for key, job in self.records.items() if job["state"] not in TERMINAL]
            self.condition.notify_all()
        for key in ids:
            self.cancel(key)
        self.thread.join(timeout=20)

    def _work(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.closed or self.queue)
                if self.closed:
                    return
                job = self.records.get(self.queue.popleft())
                if job is None or job["state"] != "queued":
                    continue
                job.update(state="running", message="Starting worker", startedAt=time.time())
                stage = None
                try:
                    # Child owns any Demucs/FFmpeg descendants. Cancellation
                    # kills that tree, never the GUI or unrelated Python jobs.
                    stage = tempfile.mkdtemp(prefix=".orbit-api-job-", dir=self.workspace)
                    options = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {"start_new_session": True}
                    process = subprocess.Popen([sys.executable, "-u", str(Path(__file__).with_name("automation_worker.py"))],
                                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                               text=True, encoding="utf-8", errors="replace", **options)
                    job["_process"] = process
                except Exception as exc:
                    if stage:
                        shutil.rmtree(stage, ignore_errors=True)
                    job.update(state="failed", error={"code": "worker_start_failed", "message": str(exc)}, finishedAt=time.time())
                    continue
            try:
                envelope = dict(request=job["_request"], workspace=self.workspace, maxRenderSeconds=self.max_render_seconds,
                                stagingDirectory=stage)
                process.stdin.write(json.dumps(envelope, ensure_ascii=False, allow_nan=False) + "\n")
                process.stdin.close()
                result, error = None, None
                for line in process.stdout:
                    try:
                        event = json.loads(line)
                    except (ValueError, TypeError):
                        continue
                    with self.condition:
                        if job["state"] != "running":
                            continue
                        if event.get("event") == "progress":
                            job.update(progress=max(0, min(1, float(event.get("value", 0)))), message=str(event.get("message", ""))[-500:])
                        elif event.get("event") == "result":
                            result = event.get("data")
                        elif event.get("event") == "error":
                            error = {k: event[k] for k in ("code", "message", "status") if k in event}
                exit_code = process.wait()
                with self.condition:
                    if job["state"] == "running":
                        if exit_code == 0 and result is not None:
                            job.update(state="succeeded", progress=1, message="Complete", result=result)
                        else:
                            job.update(state="failed", error=error or {"code": "worker_failed", "message": f"Worker exited {exit_code}"})
                        job["finishedAt"] = time.time()
            except Exception as exc:
                kill_tree(process)
                with self.condition:
                    if job["state"] == "running":
                        job.update(state="failed", error={"code": "worker_failed", "message": str(exc)}, finishedAt=time.time())
            finally:
                if process.stdout:
                    process.stdout.close()
                # stage is created by us under the validated workspace and is
                # never a caller-supplied path. Clean even after forced cancel.
                shutil.rmtree(stage, ignore_errors=True)
                with self.condition:
                    job["_process"] = None
                    job.pop("_request", None)


class ApiServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, workspace, token, port=8765, max_render_seconds=600):
        self.paths = Paths(workspace)
        if not isinstance(token, str) or len(token) < 32 or not token.isascii() or not token.isprintable():
            raise OrbitError("Token must contain at least 32 printable ASCII characters")
        number(port, "port", 0, 65535)
        number(max_render_seconds, "max-render-seconds", .01, 86410)
        self.token = token
        self.command_lock = threading.Lock()
        super().__init__(("127.0.0.1", port), Handler)
        self.jobs = Jobs(workspace, max_render_seconds)

    def server_close(self):
        if hasattr(self, "jobs"):
            self.jobs.close()
        super().server_close()


class Handler(BaseHTTPRequestHandler):
    server_version = "ORBIT/" + VERSION
    sys_version = ""

    def setup(self):
        super().setup()
        self.connection.settimeout(15)

    def log_message(self, fmt, *args):
        pass  # Request URLs/headers may contain private filenames. Never log tokens.

    def send_json(self, status, payload, headers=None):
        data = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def auth(self):
        hosts = {f"127.0.0.1:{self.server.server_port}", f"localhost:{self.server.server_port}"}
        if len(self.headers.get_all("Host", [])) != 1 or self.headers.get("Host") not in hosts:
            raise OrbitError("Invalid Host header", "host_forbidden", 403)
        # Browser pages cannot invoke a privileged filesystem API. No CORS and
        # reject even authenticated cross-origin requests, including Origin:null.
        if self.headers.get("Origin") is not None or self.headers.get("Sec-Fetch-Site") in ("cross-site", "same-site"):
            raise OrbitError("Browser origins are not enabled", "origin_forbidden", 403)
        values = self.headers.get_all("Authorization", [])
        supplied = values[0] if len(values) == 1 else ""
        if not hmac.compare_digest(supplied.encode("utf-8"), ("Bearer " + self.server.token).encode("utf-8")):
            raise OrbitError("Bearer token required", "unauthorized", 401)

    def body(self):
        lengths = self.headers.get_all("Content-Length", [])
        if self.headers.get("Transfer-Encoding") or len(lengths) != 1:
            raise OrbitError("Exactly one Content-Length is required; chunked bodies are not supported", "length_required", 411)
        try:
            length = int(lengths[0])
        except ValueError:
            raise OrbitError("Invalid Content-Length")
        if not 0 < length <= BODY_LIMIT:
            raise OrbitError("JSON body must be 1 byte–1 MiB", "body_too_large", 413)
        if self.headers.get_content_type() != "application/json":
            raise OrbitError("Content-Type must be application/json", "unsupported_media_type", 415)
        raw = self.rfile.read(length)
        if len(raw) != length:
            raise OrbitError("Incomplete body")
        def reject_constant(value):
            raise OrbitError(f"Non-finite JSON number: {value}")
        data = json.loads(raw.decode("utf-8-sig"), parse_constant=reject_constant)
        if not isinstance(data, dict):
            raise OrbitError("Request body must be a JSON object")
        return data

    def dispatch(self, method):
        try:
            self.auth()
            route = self.path
            if "?" in route or "#" in route or "%" in route:
                raise OrbitError("Use JSON body fields, not URL parameters")
            if method == "GET" and route == "/v1/health":
                result = dict(version=VERSION, workspace=str(self.server.paths.root), binaural=True, atmos=False)
            elif method == "GET" and route == "/v1/capabilities":
                from project_io import AUTOMATABLE, FORMATS, GENERATORS, MODES
                result = dict(actions=ACTIONS, jobActions=LONG_ACTIONS, formats=FORMATS,
                              generators=GENERATORS, channels=AUTOMATABLE, interpolation=MODES,
                              nodeTypes=["input", "output", "gain", "filter", "eq", "compressor", "gate", "echo", "reverb", "distortion", "mix", "hrtf", "chorus", "microshift", "diffuser", "convolution", "environment", "file", "duck"],
                              masterGraph=True, masterExcludedNodes=["hrtf", "file", "environment"],
                              sourceEdits=["trimStart", "trimEnd", "fadeIn", "fadeOut", "speed", "reverse", "invert", "normalize", "targetPeak"])
            elif method == "GET" and route == "/v1/openapi.json":
                self.send_json(200, read_json(Path(__file__).with_name("openapi.json")))
                return
            elif method == "POST" and route == "/v1/execute":
                request = self.body()
                if request.get("action") not in ("doctor", "project.read"):
                    raise OrbitError("Use POST /v1/jobs for file processing and mutations")
                with self.server.command_lock:
                    result = execute(request, self.server.paths)
            elif method == "POST" and route == "/v1/jobs":
                result = self.server.jobs.submit(self.body())
                self.send_json(202, dict(ok=True, data=result), {"Location": "/v1/jobs/" + result["id"]})
                return
            elif method == "GET" and route == "/v1/jobs":
                result = self.server.jobs.get()
            elif route.startswith("/v1/jobs/") and method in ("GET", "DELETE"):
                job_id = route[len("/v1/jobs/"):]
                if not job_id or len(job_id) != 32 or any(c not in "0123456789abcdef" for c in job_id):
                    raise OrbitError("Invalid job ID", "not_found", 404)
                result = self.server.jobs.get(job_id) if method == "GET" else self.server.jobs.cancel(job_id)
            else:
                raise OrbitError("Route or method not found", "not_found", 404)
            self.send_json(200, dict(ok=True, data=result))
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:
            code = getattr(exc, "code", "failed")
            status = getattr(exc, "status", 400)
            self.send_json(status, dict(ok=False, error=dict(code=code, message=str(exc))),
                           {"WWW-Authenticate": "Bearer"} if status == 401 else None)

    def do_GET(self):
        self.dispatch("GET")

    def do_POST(self):
        self.dispatch("POST")

    def do_DELETE(self):
        self.dispatch("DELETE")

    def do_OPTIONS(self):
        self.dispatch("OPTIONS")


def serve(workspace, port=8765, token_file=None, max_render_seconds=600):
    paths = Paths(workspace)
    token_path = Path(token_file).resolve() if token_file else paths.root / ".orbit-api-token"
    if not token_path.exists():
        token_path.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(token_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="ascii") as stream:
            stream.write(secrets.token_urlsafe(32))
    token = token_path.read_text(encoding="ascii").strip()
    with ApiServer(workspace, token, port, max_render_seconds) as server:
        # Token itself is intentionally absent from output/logs and process args.
        print(json.dumps(dict(event="listening", version=VERSION, url=f"http://127.0.0.1:{server.server_port}",
                              workspace=str(paths.root), tokenFile=str(token_path)), ensure_ascii=False), flush=True)
        try:
            server.serve_forever(poll_interval=.2)
        except KeyboardInterrupt:
            pass
