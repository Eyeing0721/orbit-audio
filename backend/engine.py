"""Free, local object-audio rendering. Coordinates: X right, Y front, Z up, metres."""
from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Callable

import h5py
import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, oaconvolve, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000
FIELDS = ("x", "y", "z", "gain", "reverb", "echo", "distortion", "spread", "lowpass")
DEFAULTS = dict(x=0., y=2., z=0., gain=0., reverb=.12, echo=0., distortion=0., spread=.2, lowpass=18000.)


def ffmpeg_path() -> str:
    local = ROOT / "tools" / "ffmpeg.exe"
    found = os.environ.get("ORBIT_FFMPEG") or (str(local) if local.exists() else shutil.which("ffmpeg"))
    if not found:
        raise RuntimeError("未找到 FFmpeg。请在设置中指定路径，或将免费 FFmpeg 放进 tools 文件夹。")
    return found


def load_audio(path: str, rate: int = RATE) -> np.ndarray:
    source = Path(path)
    if not source.is_file():
        raise FileNotFoundError(f"音频文件不存在：{path}")
    try:
        audio, sr = sf.read(source, dtype="float32", always_2d=True)
    except (RuntimeError, sf.LibsndfileError):
        try:
            result = subprocess.run([ffmpeg_path(), "-v", "error", "-i", str(source), "-ar", str(rate),
                                     "-ac", "2", "-f", "f32le", "pipe:1"], capture_output=True, check=True)
        except subprocess.CalledProcessError as error:
            details = (error.stderr or b'').decode('utf-8', errors='replace').strip()[-1800:]
            if 'does not contain any stream' in details or 'matches no streams' in details:
                raise ValueError('这个文件没有可解码的音频流，可能是仅含画面的视频分片。请导入配套音频文件或带音轨的视频。\n\n引擎详情：' + details) from error
            raise ValueError('音轨解码失败。原文件未修改。\n\n引擎详情：' + (details or str(error))) from error
        if not result.stdout:
            raise ValueError('文件未解码出音频采样，请检查是否为无音轨的视频分片。原文件未修改。')
        return np.frombuffer(result.stdout, dtype="<f4").reshape(-1, 2).copy()
    if sr != rate:
        divisor = math.gcd(sr, rate)
        audio = resample_poly(audio, rate // divisor, sr // divisor, axis=0).astype(np.float32)
    if audio.shape[1] > 2:
        raise ValueError("请先将多声道文件拆为单声道/立体声音源再导入，以免错误折叠声道。")
    return np.nan_to_num(audio)


def inspect_audio(path: str) -> dict:
    audio = load_audio(path)
    mono = np.max(np.abs(audio), axis=1)
    edges = np.linspace(0, len(mono), 641).astype(int)
    waveform = [round(float(np.max(mono[a:max(a + 1, b)])), 5) for a, b in zip(edges[:-1], edges[1:])]
    return dict(path=str(Path(path).resolve()), name=Path(path).stem, duration=len(audio) / RATE,
                sampleRate=RATE, channels=audio.shape[1], waveform=waveform)


def automation(obj: dict, times: np.ndarray | float, field: str) -> np.ndarray:
    base = float(obj.get(field, DEFAULTS.get(field, 0)))
    keys = sorted(obj.get("keyframes", []), key=lambda k: float(k["time"]))
    keys = [k for k in keys if field in k]
    if not keys:
        return np.full_like(np.asarray(times, dtype=float), base)
    xp = np.array([float(k["time"]) for k in keys])
    fp = np.array([float(k[field]) for k in keys])
    t = np.asarray(times, dtype=float)
    mode = obj.get("interpolationByField", {}).get(field, obj.get("interpolation", "smooth"))
    if mode == "step":
        return fp[np.clip(np.searchsorted(xp, t, side="right") - 1, 0, len(fp) - 1)]
    if mode == "bezier" and len(xp) > 1:
        # LUT evaluation keeps sample-rate effect curves memory bounded. Spatial
        # scalar/block queries use the same cubic with a direct root solve.
        flat = np.atleast_1d(t).reshape(-1)
        result = np.interp(flat, xp, fp)
        def cubic(u, p0, p1, p2, p3):
            v = 1-u
            return v*v*v*p0 + 3*v*v*u*p1 + 3*v*u*u*p2 + u*u*u*p3
        for index, (a,b) in enumerate(zip(keys[:-1],keys[1:])):
            mask = (flat > xp[index]) & (flat < xp[index+1])
            if not mask.any():
                continue
            lo_t,hi_t=xp[index],xp[index+1]
            t1=np.clip(a.get(f"{field}.outT",lo_t+(hi_t-lo_t)/3),lo_t,hi_t)
            t2=np.clip(b.get(f"{field}.inT",hi_t-(hi_t-lo_t)/3),lo_t,hi_t)
            v1=a.get(f"{field}.outV",fp[index]);v2=b.get(f"{field}.inV",fp[index+1])
            if mask.sum() > 4096:
                u=np.linspace(0,1,8193)
                result[mask]=np.interp(flat[mask],cubic(u,lo_t,t1,t2,hi_t),cubic(u,fp[index],v1,v2,fp[index+1]))
            else:
                low=np.zeros(mask.sum());high=np.ones(mask.sum())
                for _ in range(32):
                    u=(low+high)/2
                    left=cubic(u,lo_t,t1,t2,hi_t)<flat[mask]
                    low=np.where(left,u,low);high=np.where(left,high,u)
                result[mask]=cubic((low+high)/2,fp[index],v1,v2,fp[index+1])
        return result.reshape(t.shape)
    if mode == "smooth" and len(xp) > 1:
        idx = np.clip(np.searchsorted(xp, t, side="right") - 1, 0, len(xp) - 2)
        alpha = np.clip((t - xp[idx]) / np.maximum(xp[idx + 1] - xp[idx], 1e-9), 0, 1)
        alpha = alpha * alpha * (3 - 2 * alpha)
        return fp[idx] + alpha * (fp[idx + 1] - fp[idx])
    return np.interp(t, xp, fp)


class Hrtf:
    def __init__(self, path: str = "", rate: int = RATE):
        self.path = Path(path) if path else ROOT / "assets" / "kemar.sofa"
        if not self.path.is_file():
            raise FileNotFoundError(f"未找到 SOFA 头相关函数：{self.path}")
        with h5py.File(self.path, "r") as data:
            ir = np.array(data["Data.IR"], dtype=np.float32)
            sr = int(np.array(data["Data.SamplingRate"]).flat[0])
            pos = np.array(data["SourcePosition"])
            position_type = data["SourcePosition"].attrs.get("Type", b"spherical")
            if isinstance(position_type, bytes):
                position_type = position_type.decode()
            if position_type.lower() != "spherical" or ir.ndim != 3 or ir.shape[1] != 2:
                raise ValueError("当前支持球坐标、双耳 FIR 的 SimpleFreeFieldHRIR SOFA 文件。")
            delays = np.array(data["Data.Delay"]) if "Data.Delay" in data else None
        if delays is not None and np.any(delays):
            # Data.Delay is expressed in samples by the SOFA convention.
            delays = np.broadcast_to(delays, (len(ir), 2))
            maximum = int(np.ceil(delays.max()))
            shifted = np.zeros((len(ir), 2, ir.shape[2] + maximum + 1), np.float32)
            grid = np.arange(shifted.shape[-1])
            for i in range(len(ir)):
                for ear in range(2):
                    shifted[i, ear] = np.interp(grid - delays[i, ear], np.arange(ir.shape[-1]), ir[i, ear], left=0, right=0)
            ir = shifted
        if sr != rate:
            divisor = math.gcd(sr, rate)
            ir = resample_poly(ir, rate // divisor, sr // divisor, axis=2).astype(np.float32)
        az, el = np.deg2rad(pos[:, 0]), np.deg2rad(pos[:, 1])
        self.vectors = np.column_stack((np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)))
        self.ir = ir

    def at(self, azimuth: float, elevation: float) -> np.ndarray:
        a, e = np.deg2rad([azimuth, np.clip(elevation, -40, 90)])
        target = np.array([np.cos(e) * np.cos(a), np.cos(e) * np.sin(a), np.sin(e)])
        distances = np.maximum(1e-9, 1. - self.vectors @ target)
        indices = np.argpartition(distances, 3)[:4]
        weights = 1 / distances[indices] ** 2
        weights /= weights.sum()
        return np.einsum("i,ijk->jk", weights, self.ir[indices]).astype(np.float32)


def room_ir(rate: int, rt60: float, room: str, seed: int) -> np.ndarray:
    rt60 = float(np.clip(rt60, .15, 8))
    rng = np.random.default_rng(seed)
    n = int(rate * (rt60 + .08))
    t = np.arange(n) / rate
    noise = sosfilt(butter(2, [180, 11500 if room == "bathroom" else 6500], btype="bandpass", fs=rate, output="sos"), rng.normal(size=(n, 2)), axis=0)
    ir = noise * np.exp(-6.9078 * t[:, None] / rt60)
    ir[:int(.022 * rate)] = 0
    for i, delay in enumerate((.027, .043, .061, .089, .127, .171, .239)):
        at = int(delay * rate)
        if at < n:
            ir[at, i % 2] += 5. / (i + 1) ** .5
    ir /= max(np.sqrt(np.sum(ir ** 2) / 2), 1e-9)
    return ir.astype(np.float32)


def ambience(kind: str, seconds: float, seed: int = 71) -> np.ndarray:
    n = max(1, int(seconds * RATE))
    rng = np.random.default_rng(seed)
    t = np.arange(n, dtype=np.float32) / RATE
    noise = rng.normal(0, 1, (n, 2)).astype(np.float32)
    if kind in ("pink", "wind", "ocean"):
        noise = sosfilt(butter(2, 1800 if kind == "pink" else 900, fs=RATE, output="sos"), noise, axis=0)
    if kind == "rain":
        noise = sosfilt(butter(2, [400, 12500], btype="bandpass", fs=RATE, output="sos"), noise, axis=0)
        noise *= (.72 + .22 * np.sin(t * .37))[:, None]
        drops = np.zeros_like(noise)
        ix = rng.integers(0, n, max(1, int(seconds * 12)))
        drops[ix, rng.integers(0, 2, len(ix))] = rng.uniform(.2, 1, len(ix))
        noise += oaconvolve(drops, (np.exp(-np.arange(1800) / 150) * .6)[:, None], axes=0)[:n] * 3
    if kind == "ocean":
        noise *= (.18 + .82 * (.5 + .5 * np.sin(t * .42)) ** 2)[:, None]
    if kind == "wind":
        noise *= (.45 + .25 * np.sin(t * .6) + .18 * np.sin(t * .17))[:, None]
    noise *= .1 / max(float(np.sqrt(np.mean(noise ** 2))), 1e-8)
    fade = np.minimum(1., np.minimum(t, np.maximum(0, seconds - t)) / .18)
    return (noise * fade[:, None]).astype(np.float32)


def spatialize(audio: np.ndarray, obj: dict, hrtf: Hrtf, listener: dict, start: float, report: Callable | None = None) -> np.ndarray:
    """Windowed overlap-add updates HRIRs smoothly, including motion across keyframes."""
    frame, hop = 4096, 2048
    kernel_len = hrtf.ir.shape[2]
    n = len(audio)
    # The last overlapping frame can start beyond n; retain room for its FIR tail.
    output = np.zeros((n + kernel_len + frame + hop, 2), np.float32)
    window = np.hanning(frame + 1)[:-1].astype(np.float32)
    padded = np.pad(audio, ((hop, frame), (0, 0)))
    mono = audio.shape[1] == 1
    for pos in range(0, n + hop, hop):
        time = start + (pos - hop + frame / 2) / RATE
        x, y, z = (float(automation(obj, time, field)) - float(listener.get(field, 0)) for field in ("x", "y", "z"))
        distance = max(.15, math.sqrt(x*x + y*y + z*z))
        azimuth = math.degrees(math.atan2(-x, y)) + float(listener.get("yaw", 0))
        elevation = math.degrees(math.atan2(z, max(.001, math.hypot(x, y)))) - float(listener.get("pitch", 0))
        gain = 10 ** (float(automation(obj, time, "gain")) / 20) / max(1., distance ** .7)
        width = float(automation(obj, time, "spread")) * 55
        block = padded[pos:pos+frame] * window[:, None]
        if mono:
            ir = hrtf.at(azimuth, elevation)
            rendered = np.column_stack([fftconvolve(block[:, 0], ir[ear]) for ear in range(2)])
        else:
            left = hrtf.at(azimuth + width, elevation)
            right = hrtf.at(azimuth - width, elevation)
            rendered = np.column_stack([fftconvolve(block[:, 0], left[ear]) + fftconvolve(block[:, 1], right[ear]) for ear in range(2)]) * .7071068
        output[pos:pos+len(rendered)] += rendered * gain
    return output[hop:hop+n+kernel_len]


def render(project: dict, destination: str, start: float = 0., seconds: float | None = None, progress: Callable = lambda *a: None) -> dict:
    from dsp import edit_source, graph_history, process_graph, graph_is_binaural, validate_master_graph
    master_graph = project.get('masterGraph', {})
    validate_master_graph(master_graph)
    objects = project.get("objects", [])
    if not objects:
        raise ValueError("场景中没有声音对象，请先导入音频或添加环境音。")
    duration = float(project.get("duration", 30))
    tail = min(10., max(0., float(project.get("tail", 3))))
    end = min(duration + tail, start + seconds) if seconds is not None else duration + tail
    if end <= start:
        raise ValueError("渲染范围为空，请移动播放头或延长工程。")
    requested_start = start
    # Master effects see an absolute-time pre-roll, not a reset at the preview
    # cursor. This preserves dynamics/echo/reverb between full and partial renders.
    if master_graph and master_graph.get('enabled', False):
        start = math.floor(max(0., start - graph_history(master_graph)) * RATE / 240) * 240 / RATE
    n = int(round((end - start) * RATE))
    hrtf = Hrtf(project.get("hrtf", ""))
    mixed = np.zeros((n + 8192, 2), np.float32)
    solo = any(obj.get("solo", False) and not obj.get("mute", False) for obj in objects)
    active = [obj for obj in objects if not obj.get("mute", False) and (not solo or obj.get("solo", False))]
    for index, obj in enumerate(active):
        progress(index / max(1, len(active)) * .90, f"渲染对象 {index+1}/{len(active)} · {obj.get('name', '声音')}")
        # A pre-roll preserves delay and reverb when a preview starts mid-song.
        def uses(field, default=0):
            return obj.get(field, default) > 0 or any(k.get(field, 0) > 0 for k in obj.get("keyframes", []))
        object_history = (float(obj.get("decay", 2.6)) + .08 if uses("reverb", .12) else 0) + (float(obj.get("delayMs", 280)) / 1000 * 12 if uses("echo") else 0)
        lookback = max(9., graph_history(obj.get("nodeGraph", {})) + object_history)
        pre_start = math.floor(max(0., start - lookback) * RATE / 240) * 240 / RATE
        raw_start = int(pre_start * RATE)
        work_n = int(round((end - pre_start) * RATE))
        offset = int(round(float(obj.get("offset", 0)) * RATE))
        if obj.get("generator"):
            # Stable seed and absolute time make previews match the full render.
            source = ambience(obj["generator"], duration, int(obj.get("seed", 71)))
        else:
            source = load_audio(obj["path"])
        source = edit_source(source, obj.get("clip", {}))
        audio = np.zeros((work_n, source.shape[1]), np.float32)
        source_left, target_left = max(0, raw_start - offset), max(0, offset - raw_start)
        count = min(len(source) - source_left, work_n - target_left)
        if count > 0:
            audio[target_left:target_left+count] = source[source_left:source_left+count]
        if obj.get("loop", False) and len(source) > 0:
            absolute = np.arange(work_n) + raw_start - offset
            mask = (absolute >= 0) & (absolute < int(duration * RATE))
            audio[mask] = source[absolute[mask] % len(source)]
        cutoff = int(round((duration - pre_start) * RATE))
        if cutoff < work_n:
            audio[max(0, cutoff):] = 0
        audio = process_graph(audio, obj.get("nodeGraph", {}), hrtf=hrtf, start=pre_start, duration=duration)
        del source
        times = np.arange(work_n) / RATE + pre_start
        lowpass = float(obj.get("lowpass", 18000))
        audio = sosfilt(butter(2, [max(20, float(obj.get("highpass", 40))), np.clip(lowpass, 200, 21000)], btype="bandpass", fs=RATE, output="sos"), audio, axis=0).astype(np.float32)
        distortion = automation(obj, times, "distortion")[:, None]
        if np.max(distortion) > 0:
            drive = 1 + 18 * distortion
            audio = audio * (1 - distortion) + np.tanh(audio * drive) / np.maximum(1., np.sqrt(drive)) * distortion
        echo_mix = automation(obj, times, "echo")[:, None]
        if np.max(echo_mix) > 0:
            delay = max(1, int(float(obj.get("delayMs", 280)) * RATE / 1000))
            dry = audio.copy()
            feedback = float(np.clip(obj.get("feedback", .42), 0, .85))
            for repeat in range(1, 13):
                shift = delay * repeat
                if shift >= work_n:
                    break
                audio[shift:] += dry[:-shift] * echo_mix[shift:] * feedback ** (repeat - 1)
        reverb_mix = automation(obj, times, "reverb")[:, None]
        wet = None
        if np.max(reverb_mix) > 0:
            ir = room_ir(RATE, float(obj.get("decay", 2.6)), obj.get("room", "bathroom"), 90 + index)
            dry_mono = audio.mean(axis=1)
            wet = np.column_stack([oaconvolve(dry_mono, ir[:, ear])[:work_n] for ear in range(2)]).astype(np.float32)
            wet *= reverb_mix
            audio *= 1 - reverb_mix * .25
        trim = int(round((start - pre_start) * RATE))
        if graph_is_binaural(obj.get('nodeGraph', {})):
            # A reachable explicit HRTF node already produced headphone stereo.
            # Preserve it; only the object's animated gain applies after the graph.
            spatial = audio[trim:trim+n] * 10 ** (automation(obj, times[trim:trim+n], 'gain')[:, None] / 20)
        else:
            spatial = spatialize(audio[trim:trim+n], obj, hrtf, project.get("listener", {}), start)
        mixed[:len(spatial)] += spatial
        if wet is not None:
            # Decorrelated stereo reflections remain diffuse rather than pinned to the dry object.
            gain = 10 ** (automation(obj, times[trim:trim+n], "gain") / 20)
            mixed[:n] += wet[trim:trim+n] * gain[:, None] * .65
    mixed = np.nan_to_num(mixed[:n]) * 10 ** (float(project.get("masterGain", -3)) / 20)
    if master_graph and master_graph.get('enabled', False):
        progress(.91, '处理主输出节点链')
        mixed = process_graph(mixed, master_graph, hrtf=hrtf, start=start, duration=duration)
    trim_master = round((requested_start - start) * RATE)
    mixed = mixed[trim_master:]
    n = len(mixed)
    progress(.93, "检测峰值并写入无损音频")
    # Never boost quiet material. Apply one transparent gain only when the ceiling is exceeded.
    peak = float(np.max(np.abs(mixed), initial=0))
    ceiling = 10 ** (-1.2 / 20)
    attenuation = min(1., ceiling / max(peak, 1e-9)) if project.get("protectPeaks", True) else 1.
    mixed *= attenuation
    dest = Path(destination)
    dest.parent.mkdir(parents=True, exist_ok=True)
    fmt = project.get("format", "wav24")
    if fmt in ("mp3", "aac", "alac", "opus", "vorbis"):
        with tempfile.TemporaryDirectory(prefix="orbit_render_") as temp:
            intermediate = Path(temp) / "mix.wav"
            sf.write(intermediate, mixed, RATE, subtype="PCM_24")
            codec = {
                "mp3": ["-c:a","libmp3lame","-b:a","320k"],
                "aac": ["-c:a","aac","-b:a","320k"],
                "alac": ["-c:a","alac","-sample_fmt","s32p","-bits_per_raw_sample","24"],
                "opus": ["-c:a","libopus","-b:a","256k"],
                "vorbis": ["-c:a","libvorbis","-q:a","8"],
            }[fmt]
            subprocess.run([ffmpeg_path(), "-v", "error", "-y", "-i", str(intermediate), *codec, str(dest)], check=True, capture_output=True)
    else:
        formats={"wav24":("WAV","PCM_24"),"wav32":("WAV","FLOAT"),"wav16":("WAV","PCM_16"),"flac":("FLAC","PCM_24"),"aiff":("AIFF","PCM_24"),"caf":("CAF","FLOAT"),"w64":("W64","PCM_24")}
        if fmt not in formats:
            raise ValueError(f"不支持的输出格式：{fmt}")
        container,subtype=formats[fmt]
        sf.write(dest, mixed, RATE, subtype=subtype, format=container)
    progress(1., "渲染完成")
    return dict(path=str(dest.resolve()), duration=n / RATE, sampleRate=RATE, channels=2,
                peakDb=round(20 * math.log10(max(1e-12, float(np.max(np.abs(mixed), initial=0)))), 2),
                rmsDb=round(10 * math.log10(max(1e-24, float(np.mean(mixed ** 2, dtype=np.float64)))), 2),
                bytes=dest.stat().st_size, format=fmt,
                attenuationDb=round(20 * math.log10(max(attenuation, 1e-12)), 2), hrtf=str(hrtf.path))
