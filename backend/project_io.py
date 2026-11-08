"""Portable .orbit IO shared by the command line and local API (stdlib only)."""
from __future__ import annotations

import copy
import hashlib
import json
import math
import os
import re
import shutil
import stat
import tempfile
import zipfile
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.7.1"
STAGING_DIRECTORY = None  # Set only inside an isolated API worker.
AUTOMATABLE = ("x", "y", "z", "gain", "spread", "reverb", "echo", "distortion")
POSITION = ("x", "y", "z")
VALUES = dict(x=0, y=2, z=0, gain=-3, spread=.25, reverb=.15, echo=0,
              distortion=0, lowpass=18000, highpass=40, delayMs=280, feedback=.42, decay=2.6)
FORMATS = dict(wav24=".wav", wav32=".wav", flac=".flac", aiff=".aiff", caf=".caf",
               w64=".w64", mp3=".mp3", aac=".m4a", alac=".m4a", opus=".opus", vorbis=".ogg")
MODES = ("smooth", "linear", "step", "bezier")
GENERATORS = ("rain", "wind", "ocean", "white", "pink")
WINDOWS_DEVICES = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}
LIMITS = {**{k: (-10000, 10000) for k in POSITION}, "gain": (-120, 36),
          **{k: (0, 1) for k in ("spread", "reverb", "echo", "distortion")},
          "lowpass": (200, 21000), "highpass": (20, 20000), "delayMs": (1, 5000),
          "feedback": (0, .85), "decay": (.1, 10)}


class OrbitError(ValueError):
    def __init__(self, message, code="invalid_request", status=400):
        super().__init__(message)
        self.code, self.status = code, status


def number(value, label, low=-1e6, high=1e6):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise OrbitError(f"{label} must be a finite number")
    if not low <= value <= high:
        raise OrbitError(f"{label} must be between {low} and {high}")
    return value


def text_value(value, label, maximum=4096):
    if not isinstance(value, str) or len(value) > maximum or "\x00" in value:
        raise OrbitError(f"Invalid {label}")
    return value


def read_json(path):
    if Path(path).stat().st_size > 16 * 1024 * 1024:
        raise OrbitError("JSON exceeds 16 MiB")
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def validate(project):
    """Validate before DSP/packing. Keep the GUI's flattened scene schema intact."""
    if (not isinstance(project, dict) or isinstance(project.get("schemaVersion"), bool)
            or project.get("schemaVersion", 2) not in (1, 2)):
        raise OrbitError("Unsupported project schema")
    # Schema 1 used the same flattened fields, without channel overrides or
    # linked-data metadata. Match the GUI's backward-compatible defaults.
    project["schemaVersion"] = 2
    for k, v in dict(schemaVersion=2, name="未命名场景", hrtf="", duration=30, masterGain=-3,
                     tail=3, protectPeaks=True, listener=dict(x=0, y=0, z=0, yaw=0, pitch=0), objects=[]).items():
        project.setdefault(k, copy.deepcopy(v))
    text_value(project.get("name", ""), "name")
    text_value(project.get("hrtf", ""), "hrtf")
    if not isinstance(project.get("workspace", {}), dict):
        raise OrbitError("workspace must be an object")
    number(project.get("duration", 30), "duration", .001, 86400)
    number(project.get("tail", 3), "tail", 0, 10)
    number(project.get("masterGain", -3), "masterGain", -120, 36)
    if 'masterGraph' in project:
        from dsp import validate_master_graph
        validate_master_graph(project['masterGraph'])
    if not isinstance(project.get("protectPeaks", True), bool):
        raise OrbitError("protectPeaks must be boolean")
    listener = project.get("listener", {})
    if not isinstance(listener, dict) or set(listener) - {"x", "y", "z", "yaw", "pitch"}:
        raise OrbitError("Invalid listener")
    for k, v in listener.items():
        number(v, f"listener.{k}", -10000, 10000)
    objects = project.get("objects", [])
    if not isinstance(objects, list) or len(objects) > 1024:
        raise OrbitError("objects must be an array of at most 1024 items")
    ids = set()
    for obj in objects:
        if not isinstance(obj, dict):
            raise OrbitError("Each object must be a JSON object")
        defaults = dict(VALUES, name="声音", path="", kind="audio", colorIndex=0, duration=30, offset=0,
                        mute=False, solo=False, loop=False, generator="", interpolation="smooth", room="bathroom",
                        linkId="", interpolationByField={}, waveform=[], keyframes=[])
        for k, v in defaults.items():
            obj.setdefault(k, copy.deepcopy(v))
        oid = text_value(obj.get("id", ""), "object id", 256)
        if not oid or oid in ids:
            raise OrbitError("Object IDs must be nonempty and unique")
        ids.add(oid)
        for field in ("name", "path", "linkId", "kind", "room", "generator"):
            text_value(obj.get(field, ""), field)
        if obj.get("generator", "") not in ("", *GENERATORS):
            raise OrbitError("Unknown ambience generator")
        if obj.get("interpolation", "smooth") not in MODES:
            raise OrbitError("Unknown interpolation")
        modes = obj.get("interpolationByField", {})
        if not isinstance(modes, dict) or any(k not in AUTOMATABLE or v not in MODES for k, v in modes.items()):
            raise OrbitError("Invalid interpolationByField")
        for field in ("mute", "solo", "loop"):
            if not isinstance(obj.get(field, False), bool):
                raise OrbitError(f"{field} must be boolean")
        number(obj.get("duration", 30), "object.duration", .001, 86400)
        number(obj.get("offset", 0), "offset", 0, 86400)
        number(obj.get("colorIndex", 0), "colorIndex", 0, 10000)
        if not isinstance(obj.get("colorIndex", 0), int):
            raise OrbitError("colorIndex must be integer")
        if "seed" in obj:
            number(obj["seed"], "seed", 0, 2**32 - 1)
            if not isinstance(obj["seed"], int):
                raise OrbitError("seed must be integer")
        for field, (low, high) in LIMITS.items():
            number(obj.get(field, VALUES[field]), field, low, high)
        if "clip" in obj or "nodeGraph" in obj:
            from dsp import validate_clip, validate_graph
            validate_clip(obj.get("clip", {}))
            validate_graph(obj.get("nodeGraph", {}))
        if obj.get("highpass", 40) >= obj.get("lowpass", 18000):
            raise OrbitError("highpass must be below lowpass")
        waveform = obj.get("waveform", [])
        if not isinstance(waveform, list) or len(waveform) > 10000:
            raise OrbitError("Invalid waveform")
        for v in waveform:
            number(v, "waveform", 0, 1e6)
        keys = obj.get("keyframes", [])
        if not isinstance(keys, list) or len(keys) > 20000:
            raise OrbitError("Too many keyframes")
        seen_times = set()
        for key in keys:
            if not isinstance(key, dict) or "time" not in key:
                raise OrbitError("Each keyframe requires time")
            time = number(key["time"], "keyframe.time", 0, 86400)
            if time in seen_times:
                raise OrbitError("Duplicate keyframe time; merge channels at the same time")
            seen_times.add(time)
            for k, v in key.items():
                if k == "time":
                    continue
                field, _, handle = k.partition(".")
                if field not in AUTOMATABLE or handle not in ("", "inT", "outT", "inV", "outV"):
                    raise OrbitError(f"Unknown keyframe channel: {k}")
                if handle.endswith("T"):
                    number(v, k, 0, 86400)
                else:
                    number(v, k, *LIMITS[field])
    return project


class Paths:
    """API paths are confined to an explicitly chosen workspace, including symlinks."""
    def __init__(self, root=None):
        self.root = Path(root).resolve(strict=True) if root else None
        if self.root and not self.root.is_dir():
            raise OrbitError("Workspace must be a directory")

    def resolve(self, value, *, exists=False):
        text_value(value, "path")
        if not value:
            raise OrbitError("A path is required")
        path = Path(value)
        if self.root and not path.is_absolute():
            path = self.root / path
        path = path.resolve()
        if self.root and not path.is_relative_to(self.root):
            raise OrbitError("Path is outside the API workspace", "path_forbidden", 403)
        if self.root and any(p.startswith(".orbit-api-") for p in path.relative_to(self.root).parts):
            raise OrbitError("API internal paths are reserved", "path_forbidden", 403)
        if exists and not path.is_file():
            raise OrbitError(f"File not found: {value}", "not_found", 404)
        return path

    def display(self, path):
        value = Path(path).resolve()
        return value.relative_to(self.root).as_posix() if self.root else str(value)


def revision(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def publish(temporary, destination, overwrite=False):
    """Same-volume publication. A failed render/save never truncates the old result."""
    if overwrite:
        os.replace(temporary, destination)
    else:
        # link is exclusive on both NTFS and POSIX, unlike POSIX rename.
        os.link(temporary, destination)
        Path(temporary).unlink()


def temporary_directory(prefix, parent=None):
    return tempfile.TemporaryDirectory(prefix=prefix, dir=STAGING_DIRECTORY or parent)


def node_assets(project):
    for obj in project.get('objects', []):
        graph = obj.get('nodeGraph', {})
        nodes = graph.get('nodes', []) if isinstance(graph, dict) else []
        for node in nodes if isinstance(nodes, list) else []:
            if isinstance(node, dict) and node.get('assetPath'):
                yield node


def save_bundle(project, destination, overwrite=False):
    validate(project)
    destination = Path(destination)
    if destination.suffix.lower() != ".orbit":
        raise OrbitError("Save destination must end in .orbit")
    if destination.exists() and not overwrite:
        raise OrbitError("Output exists; use overwrite explicitly", "conflict", 409)
    data = copy.deepcopy(project)
    assets, canonical = {}, {}

    def include(path, hrtf=False):
        source = Path(path).resolve(strict=True)
        if not source.is_file():
            raise OrbitError(f"Missing asset: {source}")
        if not hrtf and source in canonical:
            return canonical[source]
        extension = re.sub("[^a-z0-9]", "", source.suffix.lower()[1:]) or "audio"
        name = "assets/hrtf.sofa" if hrtf else f"media/{len(assets):05d}.{extension}"
        assets[name] = source
        if not hrtf:
            canonical[source] = name
        return name

    # Include HRTF first so a deliberately reused audio path cannot replace it.
    data["hrtf"] = include(data.get("hrtf") or ROOT / "assets/kemar.sofa", True)
    for obj in data.get("objects", []):
        obj["path"] = "" if obj.get("generator") else include(obj.get("path", ""))
    for node in node_assets(data):
        node['assetPath'] = include(node['assetPath'])
    data["bundleVersion"] = 1
    manifest = json.dumps(data, ensure_ascii=False, allow_nan=False).encode("utf-8")
    if len(manifest) > 16 * 1024 * 1024 or len(assets) > 4095 or sum(p.stat().st_size for p in assets.values()) > 32 * 1024**3:
        raise OrbitError("Project exceeds bundle limits")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with temporary_directory(".orbit-save-", destination.parent) as temp:
        payload = Path(temp) / "payload.orbit"
        with zipfile.ZipFile(payload, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
            archive.writestr("scene.json", manifest)
            for name, source in assets.items():
                archive.write(source, name)
        publish(payload, destination, overwrite)


@contextmanager
def load_project(path, paths=None):
    paths = paths or Paths()
    source = paths.resolve(str(path), exists=True)
    if source.suffix.lower() != ".orbit":
        data = validate(read_json(source))
        for obj in data.get("objects", []):
            if not obj.get("generator"):
                obj["path"] = str(paths.resolve(str(source.parent / obj.get("path", "")), exists=True))
        if data.get("hrtf"):
            data["hrtf"] = str(paths.resolve(str(source.parent / data["hrtf"]), exists=True))
        for node in node_assets(data):
            node['assetPath'] = str(paths.resolve(str(source.parent / node['assetPath']), exists=True))
        yield data
        return
    with temporary_directory("orbit-open-") as temp, zipfile.ZipFile(source) as archive:
        items = archive.infolist()
        names, folded_names, total = set(), set(), 0
        if len(items) > 4096:
            raise OrbitError("Too many archive entries")
        for item in items:
            mode = item.external_attr >> 16
            media_name = item.filename.split("/")[-1]
            # Keep the container portable to Windows; device names and dot-only
            # or trailing-dot names must never reach filesystem extraction.
            windows_unsafe = item.filename.startswith("media/") and (
                media_name.endswith(".") or media_name.split(".")[0].upper() in WINDOWS_DEVICES)
            if (not re.fullmatch(r"scene\.json|assets/hrtf\.sofa|media/[a-zA-Z0-9_.-]+", item.filename)
                    or windows_unsafe or item.is_dir() or stat.S_ISLNK(mode)
                    or item.filename.casefold() in folded_names or item.flag_bits & 1):
                raise OrbitError("Unsafe/duplicate/encrypted archive entry")
            names.add(item.filename)
            folded_names.add(item.filename.casefold())
            total += item.file_size
            if total > 32 * 1024**3 or item.filename == "scene.json" and item.file_size > 16 * 1024**2:
                raise OrbitError("Archive exceeds size limits")
        if "scene.json" not in names:
            raise OrbitError("Bundle has no scene.json")
        data = validate(json.loads(archive.read("scene.json")))
        if data.get("bundleVersion") != 1 or data.get("hrtf") != "assets/hrtf.sofa":
            raise OrbitError("Unsupported or incomplete bundle")
        for obj in data.get("objects", []):
            if not obj.get("generator") and (obj.get("path") not in names or not obj["path"].startswith("media/")):
                raise OrbitError("Missing embedded media")
        if "assets/hrtf.sofa" not in names:
            raise OrbitError("Missing embedded HRTF")
        for node in node_assets(data):
            if node['assetPath'] not in names or not node['assetPath'].startswith('media/'):
                raise OrbitError('Missing embedded node asset')
        # Stream only allowlisted members into a fresh private directory; CRC is
        # checked by ZipExtFile. Never use extractall on an untrusted project.
        for item in items:
            if item.filename == "scene.json":
                continue
            target = Path(temp) / item.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(item) as src, target.open("xb") as dst:
                shutil.copyfileobj(src, dst, 1024 * 1024)
        for obj in data.get("objects", []):
            obj["path"] = "" if obj.get("generator") else str(Path(temp) / obj["path"])
        for node in node_assets(data):
            node['assetPath'] = str(Path(temp) / node['assetPath'])
        data["hrtf"] = str(Path(temp) / data["hrtf"])
        # Windows does not permit atomic replacement while the original ZIP
        # handle remains open. All needed media has already been copied out.
        archive.close()
        yield data
