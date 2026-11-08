"""Non-destructive source edits, a bounded audio DAG, and measured STFT analysis."""
from __future__ import annotations

import base64
from fractions import Fraction

import numpy as np
from scipy.signal import butter, fftconvolve, lfilter, resample_poly, sosfilt, stft

RATE = 48000
NODE_PARAMS = {
    "input": {}, "output": {},
    "gain": {"gain": (-60, 24, 0)},
    "filter": {"highpass": (20, 20000, 40), "lowpass": (200, 21000, 18000)},
    "eq": {"low": (-24, 24, 0), "mid": (-24, 24, 0), "high": (-24, 24, 0)},
    "compressor": {"threshold": (-60, 0, -24), "ratio": (1, 20, 4), "attack": (1, 200, 10), "release": (10, 2000, 120), "makeup": (-12, 24, 0)},
    "gate": {"threshold": (-90, -6, -45), "attack": (1, 200, 5), "release": (10, 2000, 120)},
    "echo": {"delayMs": (1, 2000, 280), "feedback": (0, .85, .42), "wet": (0, 1, .3)},
    "reverb": {"decay": (.15, 8, 2.6), "wet": (0, 1, .5)},
    "distortion": {"drive": (1, 20, 4), "wet": (0, 1, .3)},
    "mix": {"balance": (0, 1, .5)},
    "hrtf": {"azimuth": (-180, 180, 0), "elevation": (-40, 90, 0), "distance": (.15, 20, 1.5), "spread": (0, 1, .2)},
    "chorus": {"rate": (.02, 3, .23), "depthMs": (0, 10, 5), "delayMs": (12, 40, 18), "wet": (0, 1, .35)},
    "microshift": {"cents": (0, 50, 9), "delayMs": (1, 40, 12), "wet": (0, 1, .3)},
    "diffuser": {"amount": (0, .8, .55), "size": (.25, 2, 1), "wet": (0, 1, .65)},
    "convolution": {"decay": (.15, 7.5, 3.8), "predelayMs": (0, 250, 22), "wet": (0, 1, .5), "room": (0, 2, 0), "normalize": (0, 1, 1)},
    "environment": {"kind": (0, 4, 0), "gain": (-60, 12, -12), "seed": (0, 65535, 71)},
    "file": {"gain": (-60, 24, 0), "offset": (0, 86400, 0)},
    "duck": {"threshold": (-90, 0, -32), "ratio": (1, 20, 6), "attack": (1, 200, 15), "release": (10, 2000, 450), "depth": (0, 36, 12)},
}
CLIP_DEFAULTS = dict(trimStart=0, trimEnd=0, fadeIn=0, fadeOut=0, speed=1,
                     reverse=False, invert=False, normalize=False, targetPeak=-1)


def finite(value, name, lo, hi):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not np.isfinite(value) or not lo <= value <= hi:
        raise ValueError(f"{name} must be a finite number in [{lo}, {hi}]")
    return float(value)


def validate_clip(clip):
    if not isinstance(clip, dict) or set(clip) - set(CLIP_DEFAULTS):
        raise ValueError("Unknown clip setting")
    for name in ("reverse", "invert", "normalize"):
        if not isinstance(clip.get(name, False), bool):
            raise ValueError(f"clip.{name} must be boolean")
    for name in ("trimStart", "trimEnd"):
        finite(clip.get(name, 0), name, 0, 86400)
    for name in ("fadeIn", "fadeOut"):
        finite(clip.get(name, 0), name, 0, 30)
    finite(clip.get("speed", 1), "speed", .25, 4)
    finite(clip.get("targetPeak", -1), "targetPeak", -24, 0)
    if clip.get("trimEnd", 0) and clip["trimEnd"] <= clip.get("trimStart", 0):
        raise ValueError("trimEnd must be greater than trimStart (0 means source end)")


def edit_source(audio, clip):
    if not clip:
        return audio
    validate_clip(clip)
    a = round(clip.get("trimStart", 0) * RATE)
    b = round(clip["trimEnd"] * RATE) if clip.get("trimEnd") else len(audio)
    result = audio[a:min(b, len(audio))].copy()
    if not len(result):
        raise ValueError("Clip trim range is empty/outside source")
    if clip.get("reverse"):
        result = result[::-1].copy()
    speed = clip.get("speed", 1)
    if speed != 1:
        ratio = Fraction(str(speed)).limit_denominator(1000)
        result = resample_poly(result, ratio.denominator, ratio.numerator, axis=0).astype(np.float32)
    if clip.get("normalize"):
        peak = float(np.max(abs(result)))
        if peak > 1e-9:
            result *= 10 ** (clip.get("targetPeak", -1) / 20) / peak
    if clip.get("invert"):
        result *= -1
    for field, incoming in (("fadeIn", True), ("fadeOut", False)):
        count = min(len(result), round(clip.get(field, 0) * RATE))
        if count:
            ramp = np.linspace(0, 1, count, dtype=np.float32)
            if incoming:
                result[:count] *= ramp[:, None]
            else:
                result[-count:] *= ramp[::-1, None]
    return result


def validate_graph(graph):
    if not graph:
        return [], {}, {}
    if not isinstance(graph, dict) or set(graph) - {"enabled", "nodes", "edges"} or not isinstance(graph.get("enabled", False), bool):
        raise ValueError("Invalid node graph")
    nodes, edges = graph.get("nodes", []), graph.get("edges", [])
    if not isinstance(nodes, list) or not 2 <= len(nodes) <= 64 or not isinstance(edges, list) or len(edges) > 128:
        raise ValueError("Graph requires 2–64 nodes and at most 128 edges")
    lookup = {}
    for node in nodes:
        if not isinstance(node, dict) or set(node) - {"id", "type", "x", "y", "bypass", "params", "assetPath"}:
            raise ValueError("Invalid graph node")
        key, kind = node.get("id"), node.get("type")
        if not isinstance(key, str) or not key or len(key) > 128 or key in lookup or kind not in NODE_PARAMS:
            raise ValueError("Node IDs must be unique and node types supported")
        for field in ("x", "y"):
            finite(node.get(field, 0), field, -100000, 100000)
        if not isinstance(node.get("bypass", False), bool):
            raise ValueError("bypass must be boolean")
        asset = node.get("assetPath", "")
        if not isinstance(asset, str) or len(asset) > 4096 or '\x00' in asset or (asset and kind not in ('file', 'convolution')):
            raise ValueError("Invalid node asset path")
        params = node.get("params", {})
        if not isinstance(params, dict) or set(params) - set(NODE_PARAMS[kind]):
            raise ValueError("Unknown node parameter")
        for name, (lo, hi, default) in NODE_PARAMS[kind].items():
            finite(params.get(name, default), name, lo, hi)
        if kind == "filter" and params.get("highpass", 40) >= params.get("lowpass", 18000):
            raise ValueError("Node highpass must be below lowpass")
        lookup[key] = node
    if sum(n["type"] == "input" for n in nodes) != 1 or sum(n["type"] == "output" for n in nodes) != 1:
        raise ValueError("Graph needs exactly one input and one output")
    incoming, outgoing = {}, {key: [] for key in lookup}
    indegree = {key: 0 for key in lookup}
    for edge in edges:
        if not isinstance(edge, dict) or set(edge) - {"from", "to", "port"}:
            raise ValueError("Invalid graph edge")
        a, b, port = edge.get("from"), edge.get("to"), edge.get("port", "in")
        if a not in lookup or b not in lookup or lookup[a]["type"] == "output" or lookup[b]["type"] == "input":
            raise ValueError("Invalid graph connection")
        kind = lookup[b]['type']
        ports = ("a", "b") if kind == "mix" else ("in", "key") if kind == 'duck' else () if kind in ('environment', 'file') else ("in",)
        if port not in ports or (b, port) in incoming:
            raise ValueError("Each input socket accepts one cable")
        incoming[b, port] = a
        outgoing[a].append(b)
        indegree[b] += 1
    queue = [key for key, count in indegree.items() if not count]
    order = []
    while queue:
        key = queue.pop(0)
        order.append(key)
        for target in outgoing[key]:
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)
    if len(order) != len(nodes):
        raise ValueError("Feedback cycles are not allowed; use the echo node for delay feedback")
    return order, lookup, incoming


def dynamics(audio, params, gate=False):
    hop = 240  # One envelope decision per 5 ms, then interpolated per sample.
    levels = np.max(abs(audio), axis=1)
    edges = np.arange(0, len(audio), hop)
    envelope = np.maximum.reduceat(levels, edges)
    db = 20 * np.log10(np.maximum(envelope, 1e-12))
    threshold = params.get("threshold", -45 if gate else -24)
    target = np.where(db >= threshold, 1., 0.) if gate else 10 ** (-np.maximum(db - threshold, 0) * (1 - 1 / params.get("ratio", 4)) / 20)
    attack = np.exp(-hop / (RATE * params.get("attack", 5 if gate else 10) / 1000))
    release = np.exp(-hop / (RATE * params.get("release", 120) / 1000))
    gains, current = np.empty(len(target)), float(target[0])
    for i, desired in enumerate(target):
        coefficient = attack if (desired > current if gate else desired < current) else release
        current = coefficient * current + (1 - coefficient) * desired
        gains[i] = current
    interpolated = np.interp(np.arange(len(audio)), edges, gains)
    return audio * interpolated[:, None] * 10 ** (params.get("makeup", 0) / 20)


def equalize(audio, params):
    """RBJ low/high shelves and a 1 kHz peaking band, not phase-subtracted bands."""
    result = audio
    for kind, frequency in (("low", 250), ("mid", 1000), ("high", 4000)):
        db = params.get(kind, 0)
        if not db:
            continue
        amplitude = 10 ** (db / 40)
        angle = 2 * np.pi * frequency / RATE
        cosine, sine = np.cos(angle), np.sin(angle)
        if kind == "mid":
            alpha = sine / (2 * .7071)
            b = [1 + alpha * amplitude, -2 * cosine, 1 - alpha * amplitude]
            a = [1 + alpha / amplitude, -2 * cosine, 1 - alpha / amplitude]
        else:
            beta = np.sqrt(2 * amplitude) * sine
            plus, minus = amplitude + 1, amplitude - 1
            if kind == "low":
                b = [amplitude * (plus - minus * cosine + beta), 2 * amplitude * (minus - plus * cosine), amplitude * (plus - minus * cosine - beta)]
                a = [plus + minus * cosine + beta, -2 * (minus + plus * cosine), plus + minus * cosine - beta]
            else:
                b = [amplitude * (plus + minus * cosine + beta), -2 * amplitude * (minus + plus * cosine), amplitude * (plus + minus * cosine - beta)]
                a = [plus - minus * cosine + beta, 2 * (minus - plus * cosine), plus - minus * cosine - beta]
        result = lfilter(b, a, result, axis=0)
    return result


def graph_is_binaural(graph):
    if not graph or not graph.get('enabled', False):
        return False
    _, nodes, incoming = validate_graph(graph)
    pending = [k for k, n in nodes.items() if n['type'] == 'output']
    visited = set()
    while pending:
        key = pending.pop()
        if key in visited:
            continue
        visited.add(key)
        node = nodes[key]
        if node['type'] == 'hrtf' and not node.get('bypass'):
            return True
        # A duck detector is not in the audible path. Bypass mix passes only A.
        pending.extend(a for (b, port), a in incoming.items() if b == key and port != 'key' and
                       not (node.get('bypass') and node['type'] == 'mix' and port == 'b'))
    return False


def validate_master_graph(graph):
    _, nodes, _ = validate_graph(graph)
    if any(n['type'] in ('hrtf', 'file', 'environment') for n in nodes.values()):
        raise ValueError('Master graph processes existing binaural stereo: HRTF, file and environment input nodes are not allowed')


def process_graph(audio, graph, *, hrtf=None, start=0, duration=None):
    if not graph or not graph.get("enabled", False):
        return audio
    order, nodes, incoming = validate_graph(graph)
    if not len(audio):
        return audio
    # Only ancestors of output consume DSP/memory. Disconnected nodes do not run.
    output = next(k for k, n in nodes.items() if n["type"] == "output")
    needed, pending = set(), [output]
    while pending:
        key = pending.pop()
        if key not in needed:
            needed.add(key)
            pending.extend(a for (b, _), a in incoming.items() if b == key)
    values = {}
    consumers = {key: sum(b in needed and a == key for (b, _), a in incoming.items()) for key in needed}
    silence = np.zeros_like(audio)
    for key in order:
        if key not in needed:
            continue
        node, params = nodes[key], nodes[key].get("params", {})
        kind = node["type"]
        source = values.get(incoming.get((key, "a" if kind == "mix" else "in")), silence)
        if kind == "input":
            result = audio
        elif node.get("bypass") or kind == "output":
            result = source
        elif kind == "gain":
            result = source * 10 ** (params.get("gain", 0) / 20)
        elif kind == "filter":
            result = sosfilt(butter(2, [params.get("highpass", 40), params.get("lowpass", 18000)], btype="bandpass", fs=RATE, output="sos"), source, axis=0)
        elif kind == "eq":
            result = equalize(source, params)
        elif kind in ("compressor", "gate"):
            result = dynamics(source, params, kind == "gate")
        elif kind in ('chorus', 'microshift', 'diffuser', 'convolution', 'hrtf', 'environment', 'file', 'duck'):
            from spatial_nodes import chorus, microshift, diffuse, convolution, spatial_node, input_audio, duck
            if kind == 'chorus':
                result = chorus(source, params, start)
            elif kind == 'microshift':
                result = microshift(source, params, start)
            elif kind == 'diffuser':
                result = diffuse(source, params)
            elif kind == 'convolution':
                result = convolution(source, params, node.get('assetPath', ''))
            elif kind == 'hrtf':
                result = spatial_node(source, params, hrtf)
            elif kind in ('environment', 'file'):
                result = input_audio(len(audio), params, start, duration if duration is not None else start + len(audio) / RATE,
                                     node.get('assetPath', ''), kind == 'environment')
            else:
                result = duck(source, values.get(incoming.get((key, 'key'))), params)
        elif kind == "distortion":
            drive, wet = params.get("drive", 4), params.get("wet", .3)
            result = source * (1 - wet) + np.tanh(source * drive) / max(1, np.sqrt(drive)) * wet
        elif kind == "echo":
            result = source.copy()
            delay, wet, feedback = round(params.get("delayMs", 280) * RATE / 1000), params.get("wet", .3), params.get("feedback", .42)
            for repeat in range(1, 13):
                shift = delay * repeat
                if shift >= len(source):
                    break
                result[shift:] += source[:-shift] * wet * feedback ** (repeat - 1)
        elif kind == "reverb":
            from engine import room_ir
            wet = params.get("wet", .5)
            impulse = room_ir(RATE, params.get("decay", 2.6), "bathroom", 177)
            mono = source.mean(axis=1)
            reverberated = np.column_stack([fftconvolve(mono, impulse[:, ear])[:len(source)] for ear in range(2)])
            result = source * (1 - wet) + reverberated * wet
        elif kind == "mix":
            balance = params.get("balance", .5)
            other = values.get(incoming.get((key, "b")), silence)
            result = source * (1 - balance) + other * balance
        else:
            raise ValueError(f"Unknown node: {kind}")
        if not np.isfinite(result).all() or np.max(abs(result), initial=0) > 1e6:
            raise ValueError(f"Node {key} exceeds safe numeric headroom; reduce gain/feedback")
        values[key] = np.asarray(result, dtype=np.float32)
        # Release intermediate buffers after their last consumer. Long chains
        # must not retain an entire song once for every node.
        for (target, _), upstream in incoming.items():
            if target == key and upstream in consumers:
                consumers[upstream] -= 1
                if consumers[upstream] == 0:
                    values.pop(upstream, None)
    return values[output]


def graph_history(graph):
    """Conservative lookback so preview windows retain long/chained FX tails."""
    if not graph or not graph.get("enabled", False):
        return 0
    order, nodes, incoming = validate_graph(graph)
    history = {}
    for key in order:
        node, params = nodes[key], nodes[key].get("params", {})
        own = 0
        if not node.get("bypass"):
            if node["type"] == "echo":
                own = params.get("delayMs", 280) / 1000 * 12
            elif node["type"] == "reverb":
                own = params.get("decay", 2.6) + .08
            elif node["type"] in ("compressor", "gate"):
                own = params.get("release", 120) / 1000 * 8
            elif node['type'] == 'convolution':
                own = 8.4  # Includes custom IR, intrinsic/predelay and safety.
            elif node['type'] == 'diffuser':
                own = 8
            elif node['type'] in ('chorus', 'microshift', 'hrtf'):
                own = .15
            elif node['type'] == 'duck':
                own = params.get('release', 450) / 1000 * 8
        history[key] = own + max((history[a] for (b, _), a in incoming.items() if b == key), default=0)
    output = next(key for key in nodes if nodes[key]["type"] == "output")
    return history[output]


def analyze_object(obj, start=0, seconds=12, processed=True, channel="mono", progress=lambda *a: None):
    from engine import ambience, load_audio
    finite(start, "start", 0, 86400)
    finite(seconds, "seconds", .05, 30)
    if not isinstance(processed, bool) or channel not in ("mono", "left", "right"):
        raise ValueError("Invalid analysis options")
    progress(.05, "读取实际音频与源级处理")
    if obj.get("generator"):
        duration = float(obj.get("duration", 30))
        if duration > 600:
            raise ValueError("Analyze a generated ambience of 600 seconds or less")
        audio = ambience(obj["generator"], duration, int(obj.get("seed", 71)))
    else:
        audio = load_audio(obj["path"])
    if processed:
        audio = edit_source(audio, obj.get("clip", {}))
        audio = process_graph(audio, obj.get("nodeGraph", {}))
    duration = len(audio) / RATE
    a, b = round(start * RATE), min(len(audio), round((start + seconds) * RATE))
    if b <= a:
        raise ValueError("Analysis range is outside the selected source/processed clip")
    audio = audio[a:b]
    mono = audio.mean(axis=1) if channel == "mono" else audio[:, min(audio.shape[1] - 1, 1 if channel == "right" else 0)]
    progress(.45, "计算 STFT 与对数频谱")
    # Fixed FFT grid gives comparable frequency bins even for short selections.
    _, times, z = stft(np.pad(mono, (0, max(0, 2048 - len(mono)))), RATE, nperseg=2048, noverlap=1536, boundary="zeros")
    magnitudes = abs(z) * 2
    frequencies = np.geomspace(40, 20000, 192)
    bins = frequencies / RATE * 2048
    left = np.floor(bins).astype(int)
    fraction = (bins - left)[:, None]
    log_magnitude = magnitudes[left] * (1 - fraction) + magnitudes[left + 1] * fraction
    frame_indices = np.linspace(0, len(times) - 1, min(512, len(times))).astype(int)
    db = 20 * np.log10(np.maximum(log_magnitude[:, frame_indices], 1e-6))
    pixels = np.clip(np.round((db + 100) * 255 / 100), 0, 255).astype(np.uint8)
    spectrum = 20 * np.log10(np.maximum(np.sqrt(np.mean(log_magnitude ** 2, axis=1)), 1e-6))
    waveform = [float(np.max(abs(part), initial=0)) for part in np.array_split(mono, min(640, len(mono)))]
    progress(1, "频谱分析完成")
    return dict(width=pixels.shape[1], height=pixels.shape[0], pixels=base64.b64encode(pixels.tobytes()).decode("ascii"),
                frequencies=frequencies.round(2).tolist(), spectrumDb=np.maximum(spectrum, -120).round(2).tolist(),
                waveform=waveform, start=start, seconds=len(mono) / RATE, duration=duration, channel=channel, processed=processed,
                sampleRate=RATE, peakDb=round(float(20 * np.log10(max(float(np.max(abs(mono))), 1e-12))), 2),
                rmsDb=round(float(20 * np.log10(max(float(np.sqrt(np.mean(mono ** 2))), 1e-12))), 2))
