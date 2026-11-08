"""Exercise ORBIT using only new procedural projects in an owned temporary directory."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from orbit import resolve_home, resolve_python


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--orbit-home")
    parser.add_argument("--python")
    parser.add_argument("--with-mp3", action="store_true", help="Also verify FFmpeg-backed MP3 export")
    args = parser.parse_args()
    home = resolve_home(args.orbit_home)
    python = resolve_python(home, args.python)
    launcher = Path(__file__).with_name("orbit.py")
    prefix = [sys.executable, str(launcher), "--orbit-home", str(home), "--python", python]
    checks = []

    with tempfile.TemporaryDirectory(prefix="orbit-skill-check-") as temp:
        folder = Path(temp)

        def call(*arguments, request=None, error_code=None):
            process = subprocess.run(prefix + list(arguments), cwd=folder,
                                     input=json.dumps(request, ensure_ascii=False) if request is not None else None,
                                     capture_output=True, text=True, encoding="utf-8", timeout=120)
            if error_code:
                if process.returncode != 1:
                    raise AssertionError("Expected an ORBIT execution failure")
                result = json.loads(process.stderr.strip().splitlines()[-1])
                assert result["error"]["code"] == error_code, result
                return result
            if process.returncode:
                raise RuntimeError(process.stderr[-3000:] or "ORBIT command failed")
            result = json.loads(process.stdout)
            assert result["ok"], result
            return result["data"]

        def run(request, error_code=None):
            return call("run", "-", request=request, error_code=error_code)

        doctor = call("doctor")
        assert doctor["ready"], "Core engine dependencies or HRTF are missing"
        if args.with_mp3:
            assert doctor.get("ffmpeg"), "--with-mp3 requires FFmpeg"

        graph = {
            "enabled": True,
            "nodes": [{"id": "in", "type": "input"},
                      {"id": "color", "type": "gain", "params": {"gain": -1}},
                      {"id": "out", "type": "output"}],
            "edges": [{"from": "in", "to": "color"}, {"from": "color", "to": "out"}],
        }
        original = folder / "original.orbit"
        edited = folder / "edited.orbit"
        run({"action": "project.create", "output": str(original), "scene": {
            "schemaVersion": 2, "name": "技能自测 · 程序化风雨", "duration": 2,
            "tail": .25, "masterGain": -6, "protectPeaks": True,
            "objects": [
                {"id": "wind", "name": "合成风声", "generator": "wind", "duration": 2,
                 "x": 0, "y": 6, "z": .2, "gain": -8, "reverb": .1, "nodeGraph": graph},
                {"id": "rain", "name": "合成雨声", "generator": "rain", "duration": 2,
                 "x": -3, "y": -2, "z": 2, "gain": -16, "reverb": .1},
            ],
        }})
        original_hash = hashlib.sha256(original.read_bytes()).hexdigest()
        changed = run({"action": "project.edit", "path": str(original), "output": str(edited), "operations": [
            {"op": "keyframe", "id": "wind", "time": 0, "values": {"y": 6, "gain": -8, "y.outT": .6, "y.outV": 6}, "interpolation": "bezier"},
            {"op": "keyframe", "id": "wind", "time": 2, "values": {"y": 1.2, "gain": -4, "y.inT": 1.4, "y.inV": 1.2}, "interpolation": "bezier"},
            {"op": "duplicate", "id": "wind", "linked": True, "values": {"x": 3, "y": -2, "z": 2}},
        ]})
        copy_id = next(edit["id"] for edit in changed["edits"] if edit["op"] == "duplicate")
        before = call("project", "info", str(edited))
        run({"action": "project.edit", "path": str(edited), "overwrite": True,
             "ifRevision": before["revision"], "operations": [
                {"op": "set", "id": "wind", "values": {"gain": -5, "reverb": .2}},
                {"op": "project", "values": {"masterGraph": graph}},
             ]})
        after = call("project", "info", str(edited))
        objects = {obj["id"]: obj for obj in after["project"]["objects"]}
        assert objects["wind"]["gain"] == objects[copy_id]["gain"] == -5
        assert objects["wind"]["reverb"] == objects[copy_id]["reverb"] == .2
        assert (objects[copy_id]["x"], objects[copy_id]["y"], objects[copy_id]["z"]) == (3, -2, 2)
        assert objects["wind"]["keyframes"][0]["y"] == 6
        assert objects[copy_id]["keyframes"][0]["y"] == -2
        assert after["project"]["masterGraph"] == graph
        assert after["embeddedAssets"]
        checks.extend(["create/save-as/reopen", "Bezier keyframes", "linked effects and independent XYZ", "master graph round-trip"])

        edited_hash = hashlib.sha256(edited.read_bytes()).hexdigest()
        run({"action": "project.edit", "path": str(edited), "overwrite": True,
             "ifRevision": before["revision"], "operations": [
                 {"op": "set", "id": "wind", "values": {"gain": -10}},
             ]}, error_code="revision_conflict")
        assert hashlib.sha256(edited.read_bytes()).hexdigest() == edited_hash
        assert hashlib.sha256(original.read_bytes()).hexdigest() == original_hash
        checks.append("stale revision rejected; source and working file preserved")

        formats = ["flac"] + (["mp3"] if args.with_mp3 else [])
        for fmt in formats:
            destination = folder / ("result." + fmt)
            rendered = call("render", str(edited), str(destination), "--format", fmt)
            assert rendered["sampleRate"] == 48000 and rendered["channels"] == 2
            assert abs(rendered["duration"] - 2.25) < .001
            assert rendered["peakDb"] <= -1.19
            decoded = call("inspect", str(destination))
            assert decoded["sampleRate"] == 48000 and decoded["channels"] == 2
            assert abs(decoded["duration"] - 2.25) < .1
            assert max(decoded["waveform"]) > 0
            checks.append(fmt + " export and ORBIT decode-back")
        with zipfile.ZipFile(edited) as archive:
            assert archive.testzip() is None
            assert "assets/hrtf.sofa" in archive.namelist()
        checks.append("portable ZIP integrity and embedded HRTF")

    print(json.dumps({"ok": True, "engineVersion": doctor["version"], "checks": checks,
                      "userAudioUsed": False, "modelsDownloaded": False,
                      "temporaryOutputsCleaned": True}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)
