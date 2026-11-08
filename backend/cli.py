"""ORBIT automation entry point. JSON result on stdout, progress/errors on stderr."""
from __future__ import annotations

import argparse
import json
import sys

from automation import execute
from project_io import FORMATS, GENERATORS, VERSION, OrbitError, read_json


def emit(data, stream=sys.stdout):
    print(json.dumps(data, ensure_ascii=False, allow_nan=False), file=stream, flush=True)


def parser():
    root = argparse.ArgumentParser(prog="orbit", description="ORBIT local spatial audio CLI / HTTP API. No desktop control.")
    root.add_argument("--version", action="version", version=f"ORBIT {VERSION}")
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor", help="Check local engine dependencies (no model downloads)")
    inspect = commands.add_parser("inspect", help="Decode audio and report duration / waveform")
    inspect.add_argument("path")
    analysis = commands.add_parser("analyze", help="Measured source/clip/node STFT and spectrum for an object in a saved project")
    analysis.add_argument("path")
    analysis.add_argument("--object-id", dest="objectId")
    analysis.add_argument("--start", type=float, default=0)
    analysis.add_argument("--seconds", type=float, default=12)
    analysis.add_argument("--channel", choices=("mono", "left", "right"), default="mono")
    analysis.add_argument("--raw", action="store_true", help="Analyze original source before clip edits/nodes")
    run = commands.add_parser("run", help="Execute one JSON request, using the same schema as the API")
    run.add_argument("request", help="UTF-8 JSON file, or - to read stdin")
    render = commands.add_parser("render", help="Render a saved project to headphone binaural stereo")
    render.add_argument("path")
    render.add_argument("output")
    render.add_argument("--format", choices=FORMATS, default="wav24")
    render.add_argument("--start", type=float, default=0)
    render.add_argument("--seconds", type=float)
    render.add_argument("--overwrite", action="store_true")
    separate = commands.add_parser("separate", help="Demucs separation into a NEW output directory")
    separate.add_argument("path")
    separate.add_argument("output")
    separate.add_argument("--model", choices=("htdemucs_6s", "htdemucs_ft", "htdemucs"), default="htdemucs_6s")
    separate.add_argument("--parts", nargs="+", default=["vocals", "drums", "bass", "other"])
    separate.add_argument("--device", choices=("auto", "cpu"), default="auto")
    separate.add_argument("--shifts", type=int, default=1)
    project = commands.add_parser("project", help="Portable .orbit projects, objects and animation")
    edits = project.add_subparsers(dest="project_command", required=True)
    new = edits.add_parser("new", help="Create an empty portable project")
    new.add_argument("output")
    new.add_argument("--name", default="未命名场景")
    new.add_argument("--duration", type=float, default=30)
    new.add_argument("--overwrite", action="store_true")
    info = edits.add_parser("info", help="Read scene metadata, object IDs and SHA-256 revision")
    info.add_argument("path")
    for action in ("edit", "add", "set", "duplicate", "unlink", "remove", "key", "delete-key"):
        sub = edits.add_parser(action)
        sub.add_argument("path")
        sub.add_argument("--output", help="Save as another .orbit (otherwise edit in place)")
        sub.add_argument("--overwrite", action="store_true")
        sub.add_argument("--if-revision", help="Reject the edit if the input changed")
        if action == "edit":
            sub.add_argument("--operations", required=True, help="JSON file containing an edit array")
        elif action == "add":
            source = sub.add_mutually_exclusive_group(required=True)
            source.add_argument("--audio", help="Audio file to inspect and embed")
            source.add_argument("--generator", choices=GENERATORS)
            sub.add_argument("--values", type=json.loads, default={}, help="Additional object fields as JSON")
        else:
            sub.add_argument("id", help="Object ID from project info/add")
            if action in ("set", "key"):
                sub.add_argument("--values", type=json.loads, required=True, help='JSON object, e.g. {"reverb":0.7}')
            if action in ("key", "delete-key"):
                sub.add_argument("--time", type=float, required=True)
            if action == "key":
                sub.add_argument("--interpolation", choices=("smooth", "linear", "step", "bezier"))
            if action == "delete-key":
                sub.add_argument("--fields", nargs="+", help="Channels to delete; omitted means whole frame")
            if action == "duplicate":
                sub.add_argument("--linked", action="store_true", help="Share audio/effects, keep XYZ independent")
                sub.add_argument("--at", nargs=3, type=float, metavar=("X", "Y", "Z"), help="Translate base XYZ and position curves")
    serve = commands.add_parser("serve", help="Start token-authenticated HTTP API on 127.0.0.1 only")
    serve.add_argument("--workspace", required=True, help="Existing directory; all API files stay inside it")
    serve.add_argument("--port", type=int, default=8765, help="0 asks the OS to choose a free port")
    serve.add_argument("--token-file", help="Private file containing at least 32 characters; created if missing")
    serve.add_argument("--max-render-seconds", type=float, default=600)
    return root


def request_from(args):
    values = vars(args).copy()
    command = values.pop("command")
    if command == "run":
        return json.load(sys.stdin) if args.request == "-" else read_json(args.request)
    if command != "project":
        if command == "analyze":
            values["processed"] = not values.pop("raw")
        return {"action": command, **{k: v for k, v in values.items() if v is not None}}
    action = values.pop("project_command")
    if action in ("new", "info"):
        return {"action": "project.create" if action == "new" else "project.read", **values}
    request = dict(action="project.edit", path=args.path, overwrite=args.overwrite)
    if args.output:
        request["output"] = args.output
    if args.if_revision:
        request["ifRevision"] = args.if_revision
    if action == "edit":
        request["operations"] = read_json(args.operations)
        return request
    operation = {"op": {"key": "keyframe", "delete-key": "keyframe.remove"}.get(action, action)}
    if hasattr(args, "id"):
        operation["id"] = args.id
    if action == "add":
        if not isinstance(args.values, dict):
            raise OrbitError("--values must contain a JSON object")
        operation["values"] = args.values | ({"path": args.audio} if args.audio else {"generator": args.generator})
    elif action in ("set", "key"):
        operation["values"] = args.values
    if action in ("key", "delete-key"):
        operation["time"] = args.time
    if action == "key" and args.interpolation:
        operation["interpolation"] = args.interpolation
    if action == "delete-key" and args.fields:
        operation["fields"] = args.fields
    if action == "duplicate":
        operation["linked"] = args.linked
        if args.at:
            operation["values"] = dict(zip(("x", "y", "z"), args.at))
    request["operations"] = [operation]
    return request


def main(argv=None):
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    args = parser().parse_args(argv)
    try:
        if args.command == "serve":
            from local_api import serve
            serve(args.workspace, args.port, args.token_file, args.max_render_seconds)
            return 0
        result = execute(request_from(args), progress=lambda value, message: emit(
            dict(event="progress", value=value, message=message), sys.stderr))
        emit({"ok": True, "data": result})
        return 0
    except KeyboardInterrupt:
        emit({"ok": False, "error": {"code": "cancelled", "message": "Cancelled"}}, sys.stderr)
        return 130
    except Exception as exc:
        emit({"ok": False, "error": {"code": getattr(exc, "code", "failed"), "message": str(exc)}}, sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
