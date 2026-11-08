"""Real CLI/API smoke test; --separate also runs cached Demucs on a synthetic tone."""
import argparse
import json
import math
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--separate", action="store_true")
args = parser.parse_args()
summary = {}

with tempfile.TemporaryDirectory(prefix="orbit-automation-integration-") as temp:
    folder = Path(temp)
    server = subprocess.Popen([sys.executable, "-u", str(ROOT / "backend/cli.py"), "serve", "--workspace", temp, "--port", "0"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
    try:
        info = json.loads(server.stdout.readline())
        port = info["url"].rsplit(":", 1)[1]
        client = ROOT / "scripts/api_example.py"
        if not client.is_file():
            client = ROOT.parent / "scripts/api_example.py"
        result = subprocess.run([sys.executable, str(client), "--token-file", info["tokenFile"], "--port", port],
                                capture_output=True, text=True, encoding="utf-8", timeout=90, check=True)
        data = json.loads(result.stdout)
        assert (folder / data["project"]).is_file()
        assert (folder / data["audio"]["path"]).is_file()
        assert data["audio"]["duration"] == 7 and data["audio"]["channels"] == 2
        summary["httpApi"] = dict(version=info["version"], duration=7, sampleRate=48000, format="FLAC24", tokenPrinted=False)
    finally:
        server.terminate()
        server.communicate(timeout=20)
    if args.separate:
        source = folder / "synthetic.wav"
        with wave.open(str(source), "wb") as audio:
            audio.setparams((2, 2, 48000, 48000, "NONE", "not compressed"))
            audio.writeframes(b"".join(struct.pack("<hh", *(int(math.sin(i * 2 * math.pi * frequency / 48000) * 1500)
                                                          for frequency in (220, 330))) for i in range(48000)))
        request = dict(action="separate", path=str(source), output=str(folder / "stems"),
                       model="htdemucs_6s", parts=["vocals", "piano", "guitar"], device="auto")
        result = subprocess.run([sys.executable, str(ROOT / "backend/cli.py"), "run", "-"],
                                input=json.dumps(request), capture_output=True, text=True, encoding="utf-8", timeout=180)
        if result.returncode:
            raise RuntimeError(result.stderr[-3000:])
        data = json.loads(result.stdout)["data"]
        assert len(data["files"]) == 3 and all(Path(f["path"]).is_file() for f in data["files"])
        summary["separation"] = dict(model=data["model"], device=data["device"], parts=[f["part"] for f in data["files"]])

print(json.dumps(summary, ensure_ascii=False, indent=2))
