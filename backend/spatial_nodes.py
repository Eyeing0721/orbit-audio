"""Additional local DSP nodes. No external host, plugins, or cloud processing."""
from pathlib import Path

import numpy as np
from scipy.signal import lfilter, oaconvolve

RATE = 48000


def delay_read(audio, delay_at):
    """Fractional, time-varying delay with bounded temporary allocation."""
    result = np.zeros_like(audio, dtype=np.float32)
    for begin in range(0, len(audio), 262144):
        end = min(len(audio), begin + 262144)
        grid = np.arange(begin, end, dtype=np.float64)
        positions = grid - delay_at(grid / RATE) * RATE
        low = np.floor(positions).astype(np.int64)
        fraction = (positions - low).astype(np.float32)[:, None]
        valid = (low >= 0) & (low + 1 < len(audio))
        low = np.clip(low, 0, max(0, len(audio) - 2))
        block = audio[low] * (1 - fraction) + audio[np.minimum(low + 1, len(audio) - 1)] * fraction
        result[begin:end] = block * valid[:, None]
    return result


def chorus(audio, params, start):
    stereo = np.repeat(audio, 2, axis=1) if audio.shape[1] == 1 else audio
    wet = params.get('wet', .35)
    if wet == 0:
        return audio
    voices = []
    for ear in range(2):
        def delay(t):
            return (params.get('delayMs', 18) + params.get('depthMs', 5) *
                    np.sin(2 * np.pi * params.get('rate', .23) * (t + start) + ear * np.pi / 2)) / 1000
        voices.append(delay_read(stereo[:, ear:ear+1], delay)[:, 0])
    return stereo * (1 - wet) + np.column_stack(voices) * wet


def microshift(audio, params, start):
    """Two complementary delay heads per ear; opposite small pitch shifts."""
    wet = params.get('wet', .3)
    if wet == 0:
        return audio
    stereo = np.repeat(audio, 2, axis=1) if audio.shape[1] == 1 else audio
    result = np.zeros_like(stereo)
    window = .06
    for ear, direction in enumerate((-1, 1)):
        ratio = 2 ** (direction * params.get('cents', 9) / 1200)
        slope = (1 - ratio) / window
        for phase in (0., .5):
            def delay(t):
                return params.get('delayMs', 12) / 1000 + ((t + start) * slope + phase) % 1 * window
            shifted = delay_read(stereo[:, ear:ear+1], delay)[:, 0]
            # sin² windows separated by half a cycle sum exactly to one.
            for begin in range(0, len(audio), 262144):
                end = min(len(audio), begin + 262144)
                t = np.arange(begin, end) / RATE + start
                weight = np.sin(np.pi * ((t * slope + phase) % 1)) ** 2
                result[begin:end, ear] += shifted[begin:end] * weight
    return stereo * (1 - wet) + result * wet


def diffuse(audio, params):
    """Cascaded Schroeder allpasses, computed along delay-residue sequences."""
    wet, feedback = params.get('wet', .65), params.get('amount', .55)
    if wet == 0:
        return audio
    result = np.repeat(audio, 2, axis=1) if audio.shape[1] == 1 else audio.copy()
    size = params.get('size', 1)
    for ear in range(2):
        samples = result[:, ear]
        for milliseconds in (13.7, 23.9, 37.1, 53.3):
            delay = max(1, round(milliseconds * size * (1 + ear * .071) * RATE / 1000))
            padded = np.pad(samples, (0, (-len(samples)) % delay))
            samples = lfilter([-feedback, 1], [1, -feedback], padded.reshape(-1, delay), axis=0).reshape(-1)[:len(audio)]
        result[:, ear] = samples
    return audio * (1 - wet) + result * wet


def convolution(audio, params, asset_path):
    from engine import load_audio, room_ir
    wet = params.get('wet', .5)
    if wet == 0:
        return audio
    if asset_path:
        if Path(asset_path).stat().st_size > 256 * 1024**2:
            raise ValueError('IR file exceeds 256 MiB')
        impulse = load_audio(asset_path)
        if len(impulse) > 8 * RATE:
            raise ValueError('Custom impulse response must be 8 seconds or shorter')
        if not np.any(impulse):
            raise ValueError('Impulse response is silent')
        if impulse.shape[1] == 1:
            impulse = np.repeat(impulse, 2, axis=1)
        if params.get('normalize', 1) >= .5:
            impulse = impulse / max(float(np.sqrt(np.sum(impulse.astype(float) ** 2) / 2)), 1e-12)
    else:
        room = round(params.get('room', 0))
        impulse = room_ir(RATE, params.get('decay', 3.8), 'bathroom' if room == 0 else 'chamber', 401 + room)
        if room == 2:
            impulse = np.pad(impulse, ((round(.06 * RATE), 0), (0, 0)))
    predelay = round(params.get('predelayMs', 22) * RATE / 1000)
    impulse = np.pad(impulse, ((predelay, 0), (0, 0)))
    mono = audio.mean(axis=1)
    reflected = np.column_stack([oaconvolve(mono, impulse[:, ear])[:len(audio)] for ear in range(2)])
    return audio * (1 - wet) + reflected * wet


def spatial_node(audio, params, hrtf):
    from engine import Hrtf
    hrtf = hrtf or Hrtf()
    az, elevation = params.get('azimuth', 0), params.get('elevation', 0)
    spread = params.get('spread', .2) * 55
    if audio.shape[1] == 1:
        ir = hrtf.at(az, elevation)
        result = np.column_stack([oaconvolve(audio[:, 0], ir[ear])[:len(audio)] for ear in range(2)])
    else:
        left, right = hrtf.at(az + spread, elevation), hrtf.at(az - spread, elevation)
        result = np.column_stack([(oaconvolve(audio[:, 0], left[ear])[:len(audio)] +
                                   oaconvolve(audio[:, 1], right[ear])[:len(audio)]) * .7071068 for ear in range(2)])
    return result / max(1, params.get('distance', 1.5) ** .7)


def input_audio(count, params, start, duration, asset_path='', environment=False):
    from engine import ambience, load_audio
    result = np.zeros((count, 2), np.float32)
    if environment:
        kind = ('rain', 'wind', 'ocean', 'pink', 'white')[round(params.get('kind', 0))]
        source = ambience(kind, max(.001, duration), round(params.get('seed', 71)))
    elif asset_path:
        source = load_audio(asset_path)
    else:
        return result
    offset = params.get('offset', 0)
    first, target = max(0, round((start - offset) * RATE)), max(0, round((offset - start) * RATE))
    length = min(len(source) - first, count - target)
    if length > 0:
        result[target:target+length] = source[first:first+length]
    cutoff = max(0, round((duration - start) * RATE))
    result[cutoff:] = 0
    return result * 10 ** (params.get('gain', -12 if environment else 0) / 20)


def duck(audio, detector, params):
    if detector is None or not len(audio):
        return audio
    hop = 240
    edges = np.arange(0, len(audio), hop)
    envelope = np.maximum.reduceat(np.max(abs(detector), axis=1), edges)
    db = 20 * np.log10(np.maximum(envelope, 1e-12))
    reduction = np.minimum(params.get('depth', 12), np.maximum(0, db - params.get('threshold', -32)) *
                           (1 - 1 / params.get('ratio', 6)))
    attack = np.exp(-hop / (RATE * params.get('attack', 15) / 1000))
    release = np.exp(-hop / (RATE * params.get('release', 450) / 1000))
    gains, current = np.empty(len(edges)), 1.
    for i, desired in enumerate(10 ** (-reduction / 20)):
        coefficient = attack if desired < current else release
        current = coefficient * current + (1 - coefficient) * desired
        gains[i] = current
    return audio * np.interp(np.arange(len(audio)), edges, gains)[:, None]
