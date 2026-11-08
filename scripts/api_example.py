"""Run against an already-started local ORBIT API; creates unique rain-demo files."""
import argparse
import json
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--token-file", required=True)
parser.add_argument("--port", type=int, default=8765)
args = parser.parse_args()
token = Path(args.token_file).read_text(encoding="ascii").strip()
base = f"http://127.0.0.1:{args.port}"


def request(method, path, body=None):
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)["data"]


def job(body):
    info = request("POST", "/v1/jobs", body)
    while info["state"] not in ("succeeded", "failed", "cancelled"):
        time.sleep(.3)
        info = request("GET", "/v1/jobs/" + info["id"])
    if info["state"] != "succeeded":
        raise RuntimeError(info.get("error", info["state"]))
    return info["result"]


name = "api-rain-" + uuid.uuid4().hex[:8]
project = job(dict(action="project.create", output=name + ".orbit", scene=dict(
    schemaVersion=2, name="API 空间雨幕", duration=6, tail=1,
    objects=[dict(id="rain", name="后侧雨幕", generator="rain", duration=6, x=-3, y=-2, z=2,
                  gain=-6, reverb=.65, distortion=.08, room="bathroom",
                  interpolationByField={"z": "bezier"}, keyframes=[
                      {"time": 0, "z": 2, "z.outT": 2, "z.outV": 4},
                      {"time": 6, "z": 1, "z.inT": 4, "z.inV": 3}])]
)))
linked = job(dict(action="project.edit", path=project["path"], overwrite=True, ifRevision=project["revision"],
                  operations=[dict(op="duplicate", id="rain", linked=True, values=dict(x=3, y=-2, z=2))]))
audio = job(dict(action="render", path=linked["path"], output=name + ".flac", format="flac"))
print(json.dumps(dict(project=linked["path"], audio=audio), ensure_ascii=False, indent=2))
