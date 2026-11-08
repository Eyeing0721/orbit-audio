"""Real CLI processes and loopback HTTP tests; never launch/control the desktop."""
import http.client
import json
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import wave
import zipfile
from pathlib import Path
from unittest.mock import patch

from automation import execute
from local_api import ApiServer, Jobs
from project_io import OrbitError, Paths, ROOT, load_project, revision, save_bundle

CLI = Path(__file__).with_name("cli.py")


def scene():
    return dict(schemaVersion=2, name="自动化雨幕", duration=.16, tail=.04, masterGain=-6,
                objects=[dict(id="rain", name="雨幕", generator="rain", duration=.16, reverb=0, x=-2, y=1)])


class AutomationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="orbit-cli-test-")
        self.root = Path(self.temp.name)
        self.paths = Paths(self.root)
        execute(dict(action="project.create", output="场景.orbit", scene=scene()), self.paths)

    def tearDown(self):
        self.temp.cleanup()

    def cli(self, *args, request=None, success=True):
        command = [sys.executable, str(CLI), *map(str, args)]
        result = subprocess.run(command, input=json.dumps(request) if request else None, capture_output=True,
                                text=True, encoding="utf-8", cwd=self.root, timeout=45)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return json.loads(result.stdout if success else result.stderr.strip().splitlines()[-1])

    def read(self, path="场景.orbit"):
        return execute(dict(action="project.read", path=path), self.paths)

    def edit(self, operations, **extra):
        request = dict(action="project.edit", path="场景.orbit", overwrite=True,
                       ifRevision=self.read()["revision"], operations=operations)
        return execute(request | extra, self.paths)

    def test_real_cli_version_doctor_help_and_create(self):
        self.assertTrue(self.cli("doctor")["data"]["hrtf"])
        self.cli("project", "new", "new.orbit", "--name", "中文 空格", "--duration", ".2")
        self.assertEqual(self.cli("project", "info", "new.orbit")["data"]["project"]["name"], "中文 空格")
        for args in (("--help",), ("--version",), ("project", "--help"), ("serve", "--help")):
            result = subprocess.run([sys.executable, str(CLI), *args], capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0)

    def test_cli_object_linked_copy_bezier_and_render(self):
        path = self.root / "场景.orbit"
        self.cli("project", "key", path, "rain", "--time", "0", "--values", '{"x":-2,"gain":-4,"x.outT":0.03,"x.outV":-1}',
                 "--interpolation", "bezier", "--overwrite")
        result = self.cli("project", "duplicate", path, "rain", "--linked", "--at", "2", "-2", "1", "--overwrite")
        linked = result["data"]["edits"][0]["id"]
        self.cli("project", "set", path, linked, "--values", '{"gain":-8,"reverb":0.3}', "--overwrite")
        objects = self.read()["project"]["objects"]
        self.assertEqual(objects[0]["reverb"], .3)
        self.assertEqual(objects[0]["keyframes"][0]["x"], -2)
        self.assertEqual(objects[1]["keyframes"][0]["x"], 2)
        self.assertEqual(objects[1]["keyframes"][0]["x.outV"], 3)
        self.assertEqual(objects[1]["interpolationByField"]["x"], "bezier")
        output = self.root / "空间.flac"
        result = self.cli("render", path, output, "--format", "flac")
        self.assertEqual(result["data"]["sampleRate"], 48000)
        self.assertEqual(result["data"]["channels"], 2)
        self.assertAlmostEqual(result["data"]["duration"], .2)
        before = output.read_bytes()
        self.cli("render", path, output, "--format", "flac", success=False)
        self.assertEqual(output.read_bytes(), before)

    def test_atomic_edits_conflicts_and_unknown_parameters(self):
        old = revision(self.root / "场景.orbit")
        with self.assertRaises(OrbitError):
            self.edit([dict(op="set", id="rain", values=dict(gain=-10)), dict(op="set", id="missing", values=dict(gain=0))])
        self.assertEqual(revision(self.root / "场景.orbit"), old)
        for request in (
            dict(action="project.edit", path="场景.orbit", overwrite=True, operations=[dict(op="remove", id="rain")]),
            dict(action="project.edit", path="场景.orbit", overwrite=True, ifRevision="stale", operations=[dict(op="remove", id="rain")]),
            dict(action="project.create", output="场景.orbit"),
            dict(action="doctor", command="whoami"),
        ):
            with self.assertRaises(OrbitError):
                execute(request, self.paths)
        self.assertEqual(revision(self.root / "场景.orbit"), old)

    def test_channel_delete_link_sync_unlink_and_independent_duplicate(self):
        self.edit([dict(op="keyframe", id="rain", time=0, values=dict(x=-3, reverb=.5)),
                   dict(op="keyframe", id="rain", time=.1, values=dict(x=1, reverb=.9))])
        result = self.edit([dict(op="duplicate", id="rain", linked=True)])
        linked = result["edits"][0]["id"]
        self.edit([dict(op="keyframe.remove", id=linked, time=.1, fields=["reverb"])])
        objects = self.read()["project"]["objects"]
        self.assertNotIn("reverb", objects[0]["keyframes"][1])
        self.assertEqual(objects[0]["keyframes"][1]["x"], 1)
        self.edit([dict(op="unlink", id=linked), dict(op="set", id=linked, values=dict(reverb=.2))])
        objects = self.read()["project"]["objects"]
        self.assertNotEqual(objects[0]["reverb"], objects[1]["reverb"])
        other = self.edit([dict(op="duplicate", id="rain")])["edits"][0]["id"]
        self.edit([dict(op="set", id=other, values=dict(gain=-24)), dict(op="remove", id=linked)])
        self.assertEqual(len(self.read()["project"]["objects"]), 2)
        self.assertNotEqual(self.read()["project"]["objects"][0]["gain"], -24)

    def test_media_embed_deduplicate_and_survive_original_removal(self):
        source = self.root / "tone.wav"
        with wave.open(str(source), "wb") as audio:
            audio.setparams((1, 2, 48000, 4800, "NONE", "not compressed"))
            audio.writeframes(b"\x00\x00" * 4800)
        self.edit([dict(op="add", values=dict(path="tone.wav")), dict(op="add", values=dict(path="tone.wav"))])
        with zipfile.ZipFile(self.root / "场景.orbit") as archive:
            self.assertEqual(len([n for n in archive.namelist() if n.startswith("media/")]), 1)
            self.assertEqual(archive.read("media/00001.wav"), source.read_bytes()) if "media/00001.wav" in archive.namelist() else self.fail("media missing")
        source.unlink()  # This is our own synthetic fixture, never a user's audio.
        data = self.read()
        self.assertTrue(data["embeddedAssets"])
        self.assertTrue(data["project"]["objects"][1]["path"].startswith("media/"))
        with load_project(self.root / "场景.orbit", self.paths) as project:
            self.assertTrue(Path(project["objects"][1]["path"]).is_file())

    def test_root_symlink_legacy_reference_and_reserved_paths_rejected(self):
        with tempfile.TemporaryDirectory() as outside:
            file = Path(outside) / "private.json"
            file.write_text(json.dumps(scene()), encoding="utf-8")
            for value in (str(file), "../private.json", ".orbit-api-token"):
                with self.assertRaises(OrbitError):
                    self.paths.resolve(value)
            legacy = scene()
            legacy["schemaVersion"] = 1
            (self.root / "legacy.json").write_text(json.dumps(legacy), encoding="utf-8")
            self.assertEqual(self.cli("project", "info", self.root / "legacy.json")["data"]["project"]["schemaVersion"], 2)
            self.cli("project", "set", self.root / "legacy.json", "rain", "--values", '{"gain":-10}', "--output", self.root / "migrated.orbit")
            self.assertEqual(self.read("migrated.orbit")["project"]["objects"][0]["gain"], -10)
            legacy["hrtf"] = str(ROOT / "assets/kemar.sofa")
            (self.root / "legacy.json").write_text(json.dumps(legacy), encoding="utf-8")
            with self.assertRaises(OrbitError):
                execute(dict(action="project.read", path="legacy.json"), self.paths)
            try:
                (self.root / "link").symlink_to(outside, target_is_directory=True)
            except OSError:
                pass  # Windows without Developer Mode may disallow symlinks.
            else:
                try:
                    with self.assertRaises(OrbitError):
                        self.paths.resolve("link/private.json")
                finally:
                    (self.root / "link").unlink()

    def test_malicious_bundles_and_invalid_numeric_inputs(self):
        for index, name in enumerate(("../escape", "/absolute", "media/nested/escape", "media/evil\\name", "media/..", "media/NUL.wav", "media/CON")):
            path = self.root / f"unsafe{index}.orbit"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr(name, b"bad")
            with self.assertRaises(OrbitError):
                execute(dict(action="project.read", path=str(path)), self.paths)
        link = zipfile.ZipInfo("media/link.wav")
        link.create_system, link.external_attr = 3, (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(self.root / "symlink.orbit", "w") as archive:
            archive.writestr(link, "../../secret")
        with self.assertRaises(OrbitError):
            execute(dict(action="project.read", path="symlink.orbit"), self.paths)
        for values in (dict(reverb=float("nan")), dict(echo=2), dict(highpass=20000, lowpass=400), dict(mute="false")):
            with self.assertRaises(OrbitError):
                self.edit([dict(op="set", id="rain", values=values)])

    def test_render_format_bounds_and_source_protection(self):
        for request in (
            dict(action="render", path="场景.orbit", output="mix.mp3", format="flac"),
            dict(action="render", path="场景.orbit", output="mix.wav", start=float("nan")),
            dict(action="render", path="场景.orbit", output="mix.wav", seconds=-1),
            dict(action="separate", path="场景.orbit", output="stems", model="htdemucs_ft", parts=["guitar"]),
            dict(action="separate", path="场景.orbit", output="stems", shifts=100),
        ):
            with self.assertRaises(OrbitError):
                execute(request, self.paths)
        with self.assertRaises(OrbitError):
            execute(dict(action="render", path="场景.orbit", output="mix.wav"), self.paths, max_render_seconds=.1)

    def test_cli_stdin_run_and_json_failure(self):
        result = self.cli("run", "-", request=dict(action="project.read", path="场景.orbit"))
        self.assertEqual(result["data"]["project"]["name"], "自动化雨幕")
        error = self.cli("run", "-", request=dict(action="shell", command="whoami"), success=False)
        self.assertFalse(error["ok"])
        self.assertEqual(error["error"]["code"], "invalid_request")


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="orbit-http-test-")
        self.root = Path(self.temp.name)
        self.token = "test-only-token-not-a-user-secret-12345678"
        self.server = ApiServer(self.root, self.token, port=0, max_render_seconds=1)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": .02}, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.temp.cleanup()

    def http(self, method, path, data=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=30)
        actual = {"Authorization": "Bearer " + self.token}
        body = json.dumps(data, ensure_ascii=False).encode() if data is not None else None
        if body:
            actual["Content-Type"] = "application/json"
        actual.update(headers or {})
        connection.request(method, path, body=body, headers=actual)
        response = connection.getresponse()
        status, payload = response.status, json.loads(response.read())
        connection.close()
        return status, payload

    def wait(self, job_id, terminal=True):
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            status, payload = self.http("GET", "/v1/jobs/" + job_id)
            self.assertEqual(status, 200)
            job = payload["data"]
            if job["state"] in {"succeeded", "failed", "cancelled"} or not terminal and job["state"] == "running":
                return job
            time.sleep(.025)
        self.fail("Job timed out")

    def submit(self, request):
        status, payload = self.http("POST", "/v1/jobs", request)
        self.assertEqual(status, 202, payload)
        return payload["data"]["id"]

    def test_auth_host_origin_body_and_routes(self):
        self.assertEqual(self.http("GET", "/v1/health")[0], 200)
        for headers, expected in (({"Authorization": ""}, 401), ({"Authorization": "Bearer wrong"}, 401),
                                  ({"Host": "evil.example"}, 403), ({"Origin": "http://evil.example"}, 403),
                                  ({"Origin": "null"}, 403)):
            self.assertEqual(self.http("GET", "/v1/health", headers=headers)[0], expected)
        self.assertEqual(self.http("POST", "/v1/jobs", {}, {"Content-Length": str(1024 * 1024 + 1)})[0], 413)
        self.assertEqual(self.http("POST", "/v1/jobs", {}, {"Content-Type": "text/plain"})[0], 415)
        self.assertEqual(self.http("POST", "/v1/jobs", {}, {"Transfer-Encoding": "chunked"})[0], 411)
        self.assertEqual(self.http("OPTIONS", "/v1/jobs", headers={"Origin": "http://evil"})[0], 403)
        self.assertEqual(self.http("GET", "/v1/health?token=bad")[0], 400)
        self.assertEqual(self.http("GET", "/missing")[0], 404)
        self.assertEqual(self.http("GET", "/v1/jobs/bad")[0], 404)
        self.assertEqual(self.http("POST", "/v1/jobs", dict(action="render", seconds=float("nan")))[0], 400)

    def test_real_http_create_edit_read_render_and_openapi(self):
        status, spec = self.http("GET", "/v1/openapi.json")
        self.assertEqual(status, 200)
        self.assertEqual(spec["openapi"], "3.1.0")
        status, capabilities = self.http("GET", "/v1/capabilities")
        self.assertIn("flac", capabilities["data"]["formats"])
        job = self.wait(self.submit(dict(action="project.create", output="api.orbit", scene=scene())))
        self.assertEqual(job["state"], "succeeded", job)
        _, payload = self.http("POST", "/v1/execute", dict(action="project.read", path="api.orbit"))
        rev = payload["data"]["revision"]
        edit = dict(action="project.edit", path="api.orbit", overwrite=True, ifRevision=rev,
                    operations=[dict(op="set", id="rain", values=dict(x=3, reverb=.1))])
        self.assertEqual(self.wait(self.submit(edit))["state"], "succeeded")
        self.assertEqual(self.wait(self.submit(edit))["error"]["code"], "revision_conflict")
        render = self.wait(self.submit(dict(action="render", path="api.orbit", output="mix.wav")))
        self.assertEqual(render["state"], "succeeded", render)
        self.assertEqual(render["result"]["path"], "mix.wav")
        with wave.open(str(self.root / "mix.wav")) as audio:
            self.assertEqual(audio.getframerate(), 48000)
            self.assertEqual(audio.getnchannels(), 2)
        self.assertFalse(list(self.root.glob(".orbit-api-job-*")))
        status, jobs = self.http("GET", "/v1/jobs")
        self.assertEqual(status, 200)
        self.assertFalse(any("_request" in j or "_process" in j for j in jobs["data"]))

    def test_async_failures_and_api_workspace_restriction(self):
        self.assertEqual(self.http("POST", "/v1/execute", dict(action="render"))[0], 400)
        self.assertEqual(self.http("POST", "/v1/jobs", dict(action="shell"))[0], 400)
        job = self.wait(self.submit(dict(action="inspect", path="../outside.wav")))
        self.assertEqual(job["state"], "failed")
        self.assertEqual(job["error"]["code"], "path_forbidden")
        self.assertEqual(self.http("DELETE", "/v1/jobs/" + "a" * 32)[0], 404)

    def test_api_clip_graph_edit_and_real_spectral_analysis(self):
        created = self.wait(self.submit(dict(action="project.create", output="spectral.orbit", scene=scene())))
        self.assertEqual(created["state"], "succeeded")
        from test_dsp import graph
        edited = self.wait(self.submit(dict(action="project.edit", path="spectral.orbit", overwrite=True,
            ifRevision=created["result"]["revision"], operations=[dict(op="set", id="rain", values=dict(
                clip=dict(fadeIn=.01), nodeGraph=graph("gain", dict(gain=-6))))])))
        self.assertEqual(edited["state"], "succeeded", edited)
        result = self.wait(self.submit(dict(action="analyze", path="spectral.orbit", objectId="rain", seconds=.1)))
        self.assertEqual(result["state"], "succeeded", result)
        self.assertEqual(result["result"]["height"], 192)
        self.assertEqual(result["result"]["sampleRate"], 48000)
        self.assertGreater(len(result["result"]["pixels"]), 100)
        raw = self.wait(self.submit(dict(action="analyze", path="spectral.orbit", objectId="rain", seconds=.1, processed=False)))
        self.assertAlmostEqual(result["result"]["peakDb"] - raw["result"]["peakDb"], -6, delta=.5)

    def test_running_and_queued_cancellation_cleanup(self):
        save_bundle(scene(), self.root / "cancel.orbit")
        first = self.submit(dict(action="render", path="cancel.orbit", output="cancel.wav"))
        self.wait(first, terminal=False)
        second = self.submit(dict(action="render", path="cancel.orbit", output="queued.wav"))
        self.assertEqual(self.http("DELETE", "/v1/jobs/" + second)[1]["data"]["state"], "cancelled")
        self.assertEqual(self.http("DELETE", "/v1/jobs/" + first)[1]["data"]["state"], "cancelled")
        deadline = time.monotonic() + 5
        while list(self.root.glob(".orbit-api-job-*")) and time.monotonic() < deadline:
            time.sleep(.03)
        self.assertFalse(list(self.root.glob(".orbit-api-job-*")))
        self.assertFalse((self.root / "queued.wav").exists())
        self.assertTrue((self.root / "cancel.orbit").exists())

    def test_job_queue_is_bounded_and_terminal_cancel_is_idempotent(self):
        with patch.object(Jobs, "_work", lambda instance: None):
            jobs = Jobs(self.root)
            try:
                ids = [jobs.submit(dict(action="render"))["id"] for _ in range(16)]
                with self.assertRaises(OrbitError) as error:
                    jobs.submit(dict(action="render"))
                self.assertEqual(error.exception.status, 429)
                self.assertEqual(jobs.cancel(ids[0])["state"], "cancelled")
                self.assertEqual(jobs.cancel(ids[0])["state"], "cancelled")
                jobs.submit(dict(action="render"))
            finally:
                jobs.close()
        with patch.object(Jobs, "_work", lambda instance: None):
            jobs = Jobs(self.root)
            try:
                for _ in range(200):
                    job = jobs.submit(dict(action="render"))
                    jobs.cancel(job["id"])
                self.assertEqual(len(jobs.queue), 0)
                self.assertLessEqual(len(jobs.get()), 128)
            finally:
                jobs.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
