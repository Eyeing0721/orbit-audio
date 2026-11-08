"""One command dispatcher for the CLI and authenticated local HTTP API."""
from __future__ import annotations

import copy
import importlib.util
import os
import shutil
import sys
import uuid
from pathlib import Path

from project_io import (AUTOMATABLE, FORMATS, GENERATORS, MODES, POSITION, ROOT, VALUES,
                        VERSION, OrbitError, Paths, load_project, number, publish,
                        revision, save_bundle, temporary_directory, validate)

ACTIONS = ("doctor", "inspect", "analyze", "project.create", "project.read", "project.edit", "render", "separate")
LONG_ACTIONS = ("inspect", "analyze", "project.create", "project.edit", "render", "separate")
OBJECT_FIELDS = {*VALUES, "name", "path", "kind", "colorIndex", "duration", "offset", "mute", "solo",
                 "loop", "generator", "interpolation", "interpolationByField", "room", "clip", "nodeGraph"}
PROJECT_FIELDS = {"name", "duration", "tail", "masterGain", "masterGraph", "protectPeaks", "listener", "hrtf", "workspace"}


def require_keys(data, allowed):
    if not isinstance(data, dict) or set(data) - set(allowed):
        raise OrbitError(f"Expected object containing only: {', '.join(sorted(allowed))}")


def is_position(key):
    return key.split(".")[0] in POSITION


def sync_linked(project, source):
    if not source.get("linkId"):
        return
    fields = (OBJECT_FIELDS - {*POSITION, "name", "colorIndex", "interpolation", "interpolationByField"}) | {"waveform"}
    for target in project["objects"]:
        if target is source or target.get("linkId") != source["linkId"]:
            continue
        for field in fields:
            if field in source:
                target[field] = copy.deepcopy(source[field])
        modes = target.setdefault("interpolationByField", {})
        for field in AUTOMATABLE:
            if field not in POSITION:
                modes[field] = source.get("interpolationByField", {}).get(field, source.get("interpolation", "smooth"))
        merged = {}
        for obj, position in ((target, True), (source, False)):
            for key in obj.get("keyframes", []):
                values = {k: v for k, v in key.items() if k != "time" and is_position(k) == position}
                if values:
                    merged.setdefault(key["time"], {"time": key["time"]}).update(values)
        target["keyframes"] = [merged[t] for t in sorted(merged)]


def resolve_assets(project, paths):
    from project_io import node_assets
    for obj in project.get("objects", []):
        if not obj.get("generator"):
            obj["path"] = str(paths.resolve(obj.get("path", ""), exists=True))
    if project.get("hrtf"):
        project["hrtf"] = str(paths.resolve(project["hrtf"], exists=True))
    for node in node_assets(project):
        node['assetPath'] = str(paths.resolve(node['assetPath'], exists=True))


def resolve_node_values(values, paths):
    from project_io import node_assets
    for node in node_assets(dict(objects=[values])):
        node['assetPath'] = str(paths.resolve(node['assetPath'], exists=True))


def add_object(project, values, paths):
    require_keys(values, OBJECT_FIELDS)
    values = copy.deepcopy(values)
    resolve_node_values(values, paths)
    obj = dict(VALUES, id=uuid.uuid4().hex, name="声音", path="", kind="audio", colorIndex=len(project["objects"]) % 6,
               duration=project["duration"], offset=0, mute=False, solo=False, loop=False,
               generator="", interpolation="smooth", room="bathroom", linkId="", waveform=[],
               keyframes=[], interpolationByField={})
    obj.update(copy.deepcopy(values))
    if obj["generator"]:
        if obj["generator"] not in GENERATORS:
            raise OrbitError("Unknown ambience generator")
        obj["kind"], obj["path"] = "ambience", ""
    else:
        from engine import inspect_audio
        info = inspect_audio(str(paths.resolve(obj["path"], exists=True)))
        obj.update({k: info[k] for k in ("path", "duration", "waveform")})
        if "name" not in values:
            obj["name"] = info["name"]
        project["duration"] = max(project["duration"], obj["offset"] + obj["duration"])
    project["objects"].append(obj)
    return obj


def edit(project, operations, paths):
    if not isinstance(operations, list) or not 1 <= len(operations) <= 1000:
        raise OrbitError("operations must contain 1–1000 edits")
    results = []
    for operation in operations:
        require_keys(operation, {"op", "id", "values", "linked", "time", "fields", "interpolation"})
        action = operation.get("op")
        if action == "project":
            values = operation.get("values", {})
            require_keys(values, PROJECT_FIELDS)
            if values.get("hrtf"):
                values = values | {"hrtf": str(paths.resolve(values["hrtf"], exists=True))}
            project.update(copy.deepcopy(values))
            validate(project)
            results.append({"op": action})
            continue
        if action == "add":
            obj = add_object(project, operation.get("values", {}), paths)
        else:
            obj = next((o for o in project["objects"] if o["id"] == operation.get("id")), None)
            if obj is None:
                raise OrbitError("Object not found", "not_found", 404)
            if action == "set":
                values = operation.get("values", {})
                require_keys(values, OBJECT_FIELDS)
                values = copy.deepcopy(values)
                resolve_node_values(values, paths)
                if "path" in values:
                    from engine import inspect_audio
                    info = inspect_audio(str(paths.resolve(values["path"], exists=True)))
                    obj.update({k: info[k] for k in ("path", "duration", "waveform")})
                    obj["generator"] = ""
                    values = {k: v for k, v in values.items() if k != "path"}
                obj.update(copy.deepcopy(values))
                if "interpolation" in values and "interpolationByField" not in values:
                    obj["interpolationByField"] = {}
                if obj.get("generator"):
                    obj["path"] = ""
            elif action == "duplicate":
                if not isinstance(operation.get("linked", False), bool):
                    raise OrbitError("linked must be boolean")
                values = operation.get("values", {})
                require_keys(values, {"x", "y", "z", "name"})
                original = obj
                obj = copy.deepcopy(original)
                obj["id"], obj["name"] = uuid.uuid4().hex, original["name"] + " 副本"
                if operation.get("linked"):
                    obj["linkId"] = original["linkId"] = original.get("linkId") or uuid.uuid4().hex
                else:
                    obj["linkId"] = ""
                for field in POSITION:
                    if field in values:
                        target = number(values[field], field, -10000, 10000)
                        delta = target - obj.get(field, VALUES[field])
                        obj[field] = target
                        for key in obj.get("keyframes", []):
                            for k in (field, field + ".inV", field + ".outV"):
                                if k in key:
                                    key[k] += delta
                if "name" in values:
                    obj["name"] = values["name"]
                project["objects"].append(obj)
            elif action == "unlink":
                obj["linkId"] = ""
            elif action == "remove":
                project["objects"].remove(obj)
            elif action in ("keyframe", "keyframe.remove"):
                time = number(operation.get("time"), "time", 0, 86400)
                keys = obj.setdefault("keyframes", [])
                key = next((k for k in keys if abs(k["time"] - time) < 1e-6), None)
                if action == "keyframe":
                    values = operation.get("values", {})
                    if not isinstance(values, dict) or not values or "time" in values:
                        raise OrbitError("keyframe values require channels/handles, not time")
                    if key is None:
                        key = {"time": time}
                        keys.append(key)
                    key.update(copy.deepcopy(values))
                    mode = operation.get("interpolation")
                    if mode is not None:
                        if mode not in MODES:
                            raise OrbitError("Invalid interpolation")
                        for field in {k.split(".")[0] for k in values}:
                            obj.setdefault("interpolationByField", {})[field] = mode
                elif key is not None:
                    fields = operation.get("fields", list(AUTOMATABLE))
                    if not isinstance(fields, list) or not fields or any(f not in AUTOMATABLE for f in fields):
                        raise OrbitError("fields must name automatable channels")
                    for k in list(key):
                        if k.split(".")[0] in fields:
                            del key[k]
                    if len(key) == 1:
                        keys.remove(key)
                keys.sort(key=lambda k: k["time"])
            else:
                raise OrbitError(f"Unknown edit operation: {action}")
        validate(project)
        sync_linked(project, obj)
        validate(project)
        results.append({"op": action, "id": obj["id"]})
    return results


def execute(request, paths=None, progress=lambda *args: None, max_render_seconds=None):
    paths = paths or Paths()
    if not isinstance(request, dict) or request.get("action") not in ACTIONS:
        raise OrbitError(f"action must be one of {', '.join(ACTIONS)}")
    action = request["action"]
    common = {"action", "overwrite"}
    fields = {
        "doctor": set(), "inspect": {"path"},
        "analyze": {"path", "objectId", "start", "seconds", "processed", "channel"},
        "project.create": {"output", "scene", "name", "duration"},
        "project.read": {"path"},
        "project.edit": {"path", "output", "operations", "ifRevision"},
        "render": {"path", "output", "format", "start", "seconds"},
        "separate": {"path", "output", "model", "parts", "device", "shifts"},
    }[action]
    require_keys(request, common | fields)
    overwrite = request.get("overwrite", False)
    if not isinstance(overwrite, bool):
        raise OrbitError("overwrite must be boolean")
    if action == "doctor":
        ffmpeg = os.environ.get("ORBIT_FFMPEG") or (str(ROOT / "tools/ffmpeg.exe") if (ROOT / "tools/ffmpeg.exe").is_file() else shutil.which("ffmpeg"))
        packages = {name: importlib.util.find_spec(name) is not None for name in ("numpy", "scipy", "soundfile", "h5py", "torch", "demucs")}
        hrtf = (ROOT / "assets/kemar.sofa").is_file()
        return dict(version=VERSION, python=sys.executable, packages=packages, hrtf=hrtf,
                    ffmpeg=ffmpeg, ready=hrtf and all(packages[k] for k in ("numpy", "scipy", "soundfile", "h5py")))
    if action == "inspect":
        from engine import inspect_audio
        result = inspect_audio(str(paths.resolve(request.get("path"), exists=True)))
        result["path"] = paths.display(result["path"])
        return result
    if action == "project.create":
        output = paths.resolve(request.get("output"))
        data = copy.deepcopy(request.get("scene", dict(schemaVersion=2, name=request.get("name", "未命名场景"), hrtf="",
                              duration=request.get("duration", 30), masterGain=-3, tail=3, protectPeaks=True,
                              listener=dict(x=0, y=0, z=0, yaw=0, pitch=0), objects=[])))
        validate(data)
        resolve_assets(data, paths)
        save_bundle(data, output, overwrite)
        return dict(path=paths.display(output), revision=revision(output), objectIds=[o["id"] for o in data.get("objects", [])])
    source = paths.resolve(request.get("path"), exists=True)
    if action == "separate":
        if overwrite:
            raise OrbitError("Separation always requires a new output directory")
        model = request.get("model", "htdemucs_6s")
        if model not in ("htdemucs", "htdemucs_ft", "htdemucs_6s"):
            raise OrbitError("Unknown separation model")
        parts = request.get("parts", ["vocals", "drums", "bass", "other"])
        allowed = {"vocals", "drums", "bass", "other", "instrumental"} | ({"piano", "guitar"} if model == "htdemucs_6s" else set())
        if not isinstance(parts, list) or not parts or len(set(parts)) != len(parts) or any(p not in allowed for p in parts):
            raise OrbitError("Invalid parts for the selected model")
        if request.get("device", "auto") not in ("auto", "cpu"):
            raise OrbitError("device must be auto or cpu")
        shifts = request.get("shifts", 1)
        number(shifts, "shifts", 0, 10)
        if not isinstance(shifts, int):
            raise OrbitError("shifts must be an integer")
        output = paths.resolve(request.get("output"))
        if output.exists():
            raise OrbitError("Output directory exists; choose a new directory", "conflict", 409)
        output.parent.mkdir(parents=True, exist_ok=True)
        from worker import separate
        with temporary_directory(".orbit-stems-", output.parent) as temp:
            work = Path(temp) / "stems"
            result = separate(dict(request, path=str(source), output=str(work)), progress)
            os.rename(work, output)
            for info in result["files"]:
                info["path"] = paths.display(output / Path(info["path"]).relative_to(work))
        result["path"] = paths.display(output)
        return result
    before = revision(source)
    with load_project(source, paths) as project:
        if revision(source) != before:
            raise OrbitError("Project changed while reading", "revision_conflict", 409)
        if action == "analyze":
            from dsp import analyze_object
            obj = next((o for o in project.get("objects", []) if o["id"] == request.get("objectId")), None)
            if not request.get("objectId"):
                obj = next(iter(project.get("objects", [])), None)
            if obj is None:
                raise OrbitError("Analysis object not found", "not_found", 404)
            return analyze_object(obj, request.get("start", 0), request.get("seconds", 12),
                                  request.get("processed", True), request.get("channel", "mono"), progress)
        if action == "project.read":
            # Return stable embedded references, never expired extraction paths.
            data = copy.deepcopy(project)
            if source.suffix.lower() == ".orbit":
                data["hrtf"] = "assets/hrtf.sofa"
                for obj in data.get("objects", []):
                    if not obj.get("generator"):
                        obj["path"] = "media/" + Path(obj["path"]).name
                from project_io import node_assets
                for node in node_assets(data):
                    node['assetPath'] = 'media/' + Path(node['assetPath']).name
            else:
                if data.get("hrtf"):
                    data["hrtf"] = paths.display(data["hrtf"])
                for obj in data.get("objects", []):
                    if obj.get("path"):
                        obj["path"] = paths.display(obj["path"])
                from project_io import node_assets
                for node in node_assets(data):
                    node['assetPath'] = paths.display(node['assetPath'])
            return dict(path=paths.display(source), revision=before, embeddedAssets=source.suffix.lower() == ".orbit", project=data)
        output = paths.resolve(request.get("output", str(source) if action == "project.edit" else None))
        if output.exists() and not overwrite:
            raise OrbitError("Output exists; use overwrite explicitly", "conflict", 409)
        if action == "project.edit":
            expected = request.get("ifRevision")
            if paths.root and output == source and not expected:
                raise OrbitError("In-place API edits require ifRevision from project.read", "revision_required", 428)
            if expected is not None and expected != before:
                raise OrbitError("Project changed; read it again before editing", "revision_conflict", 409)
            edits = edit(project, request.get("operations"), paths)
            if revision(source) != before:
                raise OrbitError("Project changed during editing", "revision_conflict", 409)
            save_bundle(project, output, overwrite)
            return dict(path=paths.display(output), revision=revision(output), edits=edits)
        if action != "render":
            raise OrbitError("Unsupported action")
        fmt = request.get("format", "wav24")
        if fmt not in FORMATS or output.suffix.lower() != FORMATS[fmt]:
            raise OrbitError(f"format and output extension must match: {FORMATS}")
        # Never allow an audio render to overwrite its input media, even with --overwrite.
        inputs = {source, Path(project.get("hrtf") or ROOT / "assets/kemar.sofa").resolve()}
        inputs.update(Path(o["path"]).resolve() for o in project.get("objects", []) if o.get("path"))
        from project_io import node_assets
        inputs.update(Path(n['assetPath']).resolve() for n in node_assets(project))
        if output in inputs:
            raise OrbitError("Render output must not replace a project or source asset")
        start = number(request.get("start", 0), "start", 0, 86400)
        seconds = request.get("seconds")
        if seconds is not None:
            number(seconds, "seconds", .001, 86410)
        length = min(project.get("duration", 30) + project.get("tail", 3) - start, seconds or 86410)
        if max_render_seconds and (length > max_render_seconds or min(project.get("duration", 30), start + length) > max_render_seconds):
            # The current DSP generates ambience from time zero and loads full
            # sources. Bound absolute span too, not just the preview's duration.
            raise OrbitError(f"API render span exceeds {max_render_seconds:g}s; use CLI or raise --max-render-seconds")
        output.parent.mkdir(parents=True, exist_ok=True)
        from engine import render
        with temporary_directory(".orbit-render-", output.parent) as temp:
            payload = Path(temp) / ("mix" + FORMATS[fmt])
            result = render(project | {"format": fmt}, str(payload), start, seconds, progress)
            publish(payload, output, overwrite)
        result["path"] = paths.display(output)
        result["hrtf"] = "embedded" if source.suffix.lower() == ".orbit" else project.get("hrtf") or "builtin:kemar"
        return result
