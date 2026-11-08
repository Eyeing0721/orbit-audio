import base64
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import soundfile as sf

from dsp import RATE, NODE_PARAMS, analyze_object, edit_source, process_graph, validate_clip, validate_graph
from engine import render


def graph(kind="gain", params=None):
    return dict(enabled=True, nodes=[dict(id="i", type="input"), dict(id="fx", type=kind, params=params or {}), dict(id="o", type="output")],
                edges=[dict(**{"from": "i", "to": "fx", "port": "in"}), dict(**{"from": "fx", "to": "o", "port": "in"})])


class DspTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="orbit-dsp-test-")
        self.root = Path(self.temp.name)
        self.tone = np.column_stack([np.sin(np.arange(RATE) / RATE * 2 * np.pi * hz) * .2 for hz in (440, 1000)]).astype(np.float32)
        self.source = self.root / "tone.wav"
        sf.write(self.source, self.tone, RATE, subtype="FLOAT")

    def tearDown(self):
        self.temp.cleanup()

    def test_trim_reverse_speed_fades_and_original_unchanged(self):
        before = self.tone.copy()
        clip = dict(trimStart=.1, trimEnd=.7, reverse=True, speed=2, fadeIn=.01, fadeOut=.02)
        result = edit_source(self.tone, clip)
        self.assertEqual(len(result), round(.3 * RATE))
        np.testing.assert_array_equal(result[0], 0)
        np.testing.assert_array_equal(result[-1], 0)
        np.testing.assert_array_equal(self.tone, before)
        reverse = edit_source(self.tone, dict(trimStart=.1, trimEnd=.2, reverse=True, invert=True))
        np.testing.assert_array_equal(reverse, -self.tone[4800:9600][::-1])

    def test_normalization_silence_and_invalid_edits(self):
        result = edit_source(self.tone, dict(normalize=True, targetPeak=-3))
        self.assertAlmostEqual(float(np.max(abs(result))), 10 ** (-3 / 20), places=6)
        self.assertEqual(float(np.max(abs(edit_source(self.tone * 0, dict(normalize=True))))), 0)
        for clip in (dict(speed=0), dict(fadeIn=float("nan")), dict(trimStart=2, trimEnd=1), dict(reverse="true"), dict(unknown=1)):
            with self.assertRaises(ValueError):
                validate_clip(clip)
        with self.assertRaises(ValueError):
            edit_source(self.tone, dict(trimStart=10))

    def test_all_node_types_finite_and_bypass(self):
        for kind in NODE_PARAMS:
            if kind in ("input", "output", "mix", "environment", "file"):
                continue
            settings = graph(kind)
            before = self.tone.copy()
            result = process_graph(self.tone, settings)
            self.assertEqual(result.shape, self.tone.shape, kind)
            self.assertTrue(np.isfinite(result).all(), kind)
            np.testing.assert_array_equal(self.tone, before)
            settings["nodes"][1]["bypass"] = True
            np.testing.assert_array_equal(process_graph(self.tone, settings), self.tone)
        np.testing.assert_allclose(process_graph(self.tone, graph("eq")), self.tone, atol=1e-7)
        np.testing.assert_allclose(process_graph(self.tone, graph("gain", dict(gain=6))), self.tone * 10 ** (.3), atol=1e-7)
        self.assertEqual(process_graph(self.tone[:, :1], graph("reverb")).shape[1], 2)

    def test_parallel_branch_mix_and_disconnected_output(self):
        settings = graph()
        settings["nodes"].insert(2, dict(id="parallel", type="gain", params=dict(gain=-6)))
        settings["nodes"].insert(3, dict(id="mix", type="mix", params=dict(balance=.25)))
        settings["edges"] = [{"from": "i", "to": "fx"}, {"from": "i", "to": "parallel"},
                              {"from": "fx", "to": "mix", "port": "a"}, {"from": "parallel", "to": "mix", "port": "b"}, {"from": "mix", "to": "o"}]
        expected = self.tone * (.75 + .25 * 10 ** (-6 / 20))
        np.testing.assert_allclose(process_graph(self.tone, settings), expected, atol=1e-7)
        settings["edges"] = []
        self.assertEqual(float(np.max(abs(process_graph(self.tone, settings)))), 0)

    def test_graph_cycle_ports_limits_and_unknown_parameters_rejected(self):
        bad = []
        cyclic = graph()
        cyclic["nodes"].insert(2, dict(id="b", type="gain"))
        cyclic["edges"] = [{"from": "fx", "to": "b"}, {"from": "b", "to": "fx"}, {"from": "fx", "to": "o"}]
        bad.append(cyclic)
        duplicate = graph(); duplicate["edges"].append({"from": "i", "to": "fx"}); bad.append(duplicate)
        wrong = graph(); wrong["edges"][0]["port"] = "b"; bad.append(wrong)
        bad.append(graph("gain", dict(command="exec")))
        bad.append(graph("filter", dict(highpass=18000, lowpass=200)))
        for settings in bad:
            with self.assertRaises(ValueError):
                validate_graph(settings)

    def test_compression_gate_and_equalizer_are_audible_not_metadata(self):
        compressed = process_graph(self.tone, graph("compressor", dict(threshold=-40, ratio=10)))
        self.assertLess(float(np.max(abs(compressed))), float(np.max(abs(self.tone))) / 3)
        gated = process_graph(self.tone * .001, graph("gate"))
        self.assertEqual(float(np.max(abs(gated))), 0)
        bass = np.tile((np.sin(np.arange(RATE) / RATE * 2 * np.pi * 100) * .1)[:, None], (1, 2)).astype(np.float32)
        equalized = process_graph(bass, graph("eq", dict(low=12)))
        self.assertGreater(float(np.mean(equalized[:, 0] ** 2)), float(np.mean(bass[:, 0] ** 2)) * 8)

    def test_actual_stft_tone_frequency_amplitude_and_serialization(self):
        data = analyze_object(dict(path=str(self.source)), seconds=.5, channel="left")
        frequencies = np.asarray(data["frequencies"])
        spectrum = np.asarray(data["spectrumDb"])
        self.assertLess(abs(frequencies[np.argmax(spectrum)] - 440), 35)
        self.assertAlmostEqual(data["peakDb"], -13.98, places=1)
        self.assertAlmostEqual(data["rmsDb"], -16.99, places=1)
        self.assertEqual(len(base64.b64decode(data["pixels"])), data["width"] * data["height"])
        self.assertLessEqual(data["width"], 512)
        json.dumps(data, allow_nan=False)
        right = analyze_object(dict(path=str(self.source)), seconds=.5, channel="right")
        self.assertLess(abs(frequencies[np.argmax(right["spectrumDb"])] - 1000), 60)

    def test_analysis_source_vs_processed_clip_and_graph(self):
        obj = dict(path=str(self.source), clip=dict(trimStart=.2, trimEnd=.7, speed=2), nodeGraph=graph("gain", dict(gain=-6)))
        processed = analyze_object(obj, seconds=1, channel="left")
        raw = analyze_object(obj, seconds=1, processed=False, channel="left")
        self.assertAlmostEqual(processed["duration"], .25)
        self.assertAlmostEqual(raw["duration"], 1)
        self.assertAlmostEqual(processed["peakDb"] - raw["peakDb"], -6, delta=.1)
        self.assertLess(abs(np.asarray(processed["frequencies"])[np.argmax(processed["spectrumDb"])] - 880), 60)
        with self.assertRaises(ValueError):
            analyze_object(obj, start=5)

    def test_nodes_and_clips_change_real_binaural_render(self):
        obj = dict(path=str(self.source), reverb=0, gain=-6, x=1, y=2)
        project = dict(duration=.3, tail=0, objects=[obj], protectPeaks=False)
        first, second, third = (self.root / name for name in ("plain.wav", "gain.wav", "reverse.wav"))
        render(project, str(first))
        obj["nodeGraph"] = graph("gain", dict(gain=-12))
        render(project, str(second))
        a, _ = sf.read(first); b, _ = sf.read(second)
        np.testing.assert_allclose(b, a * 10 ** (-12 / 20), atol=2e-7)
        obj["nodeGraph"] = {}
        obj["clip"] = dict(reverse=True, fadeIn=.1)
        render(project, str(third))
        c, _ = sf.read(third)
        self.assertGreater(float(np.max(abs(c - a))), .001)

    def test_node_reverb_keeps_its_tail_after_scene_end(self):
        obj = dict(path=str(self.source), reverb=0, gain=-6, x=1, y=2, nodeGraph=graph("reverb", dict(decay=.5, wet=.8)))
        path = self.root / "tail.wav"
        render(dict(duration=.1, tail=.4, objects=[obj]), str(path))
        audio, _ = sf.read(path)
        self.assertGreater(float(np.sum(audio[int(.25 * RATE):] ** 2)), .00001)

    def test_long_delay_history_survives_preview_start(self):
        source = self.root / "short.wav"
        sf.write(source, self.tone[:RATE // 5], RATE)
        obj = dict(path=str(source), reverb=0, echo=0, gain=-6, x=1, y=2,
                   nodeGraph=graph("echo", dict(delayMs=1000, feedback=.85, wet=1)))
        path = self.root / "late.wav"
        render(dict(duration=13, tail=0, objects=[obj]), str(path), start=12, seconds=.3)
        audio, _ = sf.read(path)
        self.assertGreater(float(np.sum(audio ** 2)), .001)

    def test_cli_analysis_and_portable_graph_edit(self):
        cli = Path(__file__).with_name("cli.py")
        project = self.root / "nodes.orbit"
        request = dict(action="project.create", output=str(project), scene=dict(name="nodes", duration=1,
            objects=[dict(id="tone", path=str(self.source), clip=dict(fadeIn=.01), nodeGraph=graph("gain", dict(gain=-6)))]))
        result = subprocess.run([sys.executable, str(cli), "run", "-"], input=json.dumps(request), capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([sys.executable, str(cli), "analyze", str(project), "--object-id", "tone", "--seconds", ".2", "--channel", "left"], capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)["data"]
        self.assertAlmostEqual(data["peakDb"], -19.98, places=1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
