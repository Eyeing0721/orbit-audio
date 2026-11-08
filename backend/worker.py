"""JSON-lines subprocess bridge. Audio stays on this computer; model weights download on first use."""
from __future__ import annotations

import contextlib
import importlib.util
import json
import os
import subprocess
import sys
import traceback
from pathlib import Path

os.environ.setdefault("PYTHONIOENCODING", "utf-8")
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

from engine import ROOT, inspect_audio, render


def emit(event: str, **data):
    print(json.dumps(dict(event=event, **data), ensure_ascii=False), flush=True)


def separate(request: dict, progress=None) -> dict:
    if progress is None:
        progress = lambda value, message: emit("progress", value=value, message=message)
    model = request.get("model", "htdemucs_6s")
    if model not in ("htdemucs", "htdemucs_ft", "htdemucs_6s"):
        raise ValueError("未知拆分模型")
    source = Path(request["path"])
    output = Path(request["output"])
    if not source.is_file():
        raise FileNotFoundError(str(source))
    parts = request.get("parts", ["vocals", "drums", "bass", "other"])
    allowed = {"vocals", "drums", "bass", "other", "guitar", "piano", "instrumental"}
    if not parts or any(p not in allowed for p in parts):
        raise ValueError("请选择有效拆分部件")
    import torch
    device = "cuda" if torch.cuda.is_available() and request.get("device", "auto") != "cpu" else "cpu"
    command = [sys.executable, "-u", "-m", "demucs", "-n", model, "-d", device,
               "--float32", "--shifts", str(int(request.get("shifts", 1))), "-o", str(output), str(source)]
    progress(.03, f"加载 {model} · {device} · 首次运行会下载免费模型")
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    import re
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        match = re.search(r"(\d+)%", line)
        progress(.05 + .85 * int(match.group(1)) / 100 if match else .08, line[-220:])
    if proc.wait() != 0:
        raise RuntimeError("模型拆分失败。请查看任务日志，确认显存、FFmpeg 和模型下载连接。")
    folder = output / model / source.stem
    candidates = {p.stem: p for p in folder.glob("*.wav")}
    if "instrumental" in parts and "vocals" in candidates:
        from engine import load_audio, RATE
        import soundfile as sf
        import numpy as np
        arrays = [load_audio(str(p)) for name, p in candidates.items() if name != "vocals"]
        n = max(map(len, arrays))
        mix = np.zeros((n, 2), np.float32)
        for audio in arrays:
            mix[:len(audio)] += audio
        instrumental = folder / "instrumental.wav"
        sf.write(instrumental, mix, RATE, subtype="FLOAT")
        candidates["instrumental"] = instrumental
    files = [inspect_audio(str(candidates[part])) | {"part": part} for part in parts if part in candidates]
    if len(files) != len(parts):
        raise RuntimeError("所选模型没有生成全部指定部件，请使用 6 部件模型拆吉他和钢琴。")
    return dict(files=files, device=device, model=model)


def main():
    request = json.loads(sys.stdin.readline())
    action = request.get("action")
    if action == "inspect":
        result = inspect_audio(request["path"])
    elif action == "analyze":
        from dsp import analyze_object
        result = analyze_object(request["object"], float(request.get("start", 0)), float(request.get("seconds", 12)),
                                request.get("processed", True), request.get("channel", "mono"),
                                lambda value, message: emit("progress", value=value, message=message))
    elif action == "render":
        result = render(request["project"], request["output"], float(request.get("start", 0)), request.get("seconds"),
                        lambda value, message: emit("progress", value=value, message=message))
    elif action == "separate":
        result = separate(request)
    elif action == "doctor":
        result = dict(python=sys.executable, hrtf=(ROOT / "assets/kemar.sofa").is_file(),
                      demucs=bool(importlib.util.find_spec("demucs")), root=str(ROOT))
    else:
        raise ValueError(f"未知任务：{action}")
    emit("result", data=result)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        traceback.print_exc(file=sys.stderr)
        emit("error", message=str(exc))
        sys.exit(1)
