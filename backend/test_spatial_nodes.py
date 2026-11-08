import copy
import tempfile
import subprocess
import unittest
from unittest.mock import patch
from pathlib import Path

import numpy as np
import soundfile as sf

from dsp import RATE, graph_is_binaural, process_graph, validate_graph
from engine import render
from project_io import Paths, load_project, save_bundle
from automation import execute
from test_dsp import graph


class SpatialNodesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='orbit-spatial-nodes-')
        self.root = Path(self.temp.name)
        t = np.arange(RATE) / RATE
        self.audio = np.column_stack([np.sin(2*np.pi*440*t)*.1] * 2).astype(np.float32)
        self.path = self.root / 'source.wav'
        sf.write(self.path, self.audio, RATE, subtype='FLOAT')

    def tearDown(self):
        self.temp.cleanup()

    def test_modulation_diffusion_wet_zero_and_nonzero(self):
        for kind in ('chorus', 'microshift', 'diffuser', 'convolution'):
            np.testing.assert_array_equal(process_graph(self.audio, graph(kind, dict(wet=0))), self.audio)
            out = process_graph(self.audio, graph(kind))
            self.assertTrue(np.isfinite(out).all())
            self.assertGreater(float(np.max(abs(out - self.audio))), .01, kind)
            self.assertGreater(float(np.max(abs(out[:, 0] - out[:, 1]))), .001, kind)

    def test_microshift_shifts_frequency_in_opposite_directions(self):
        from spatial_nodes import microshift
        t = np.arange(RATE * 4) / RATE
        mono = np.sin(2*np.pi*1000*t).astype(np.float32)[:, None]
        out = microshift(mono, dict(cents=35, wet=1), 0)[RATE:]
        f = np.fft.rfftfreq(len(out), 1/RATE)
        peaks = f[np.argmax(abs(np.fft.rfft(out, axis=0)), axis=0)]
        self.assertLess(abs(peaks[0] - 1000 * 2**(-35/1200)), 2)
        self.assertLess(abs(peaks[1] - 1000 * 2**(35/1200)), 2)

    def test_diffuser_retains_energy_after_impulse(self):
        signal = np.zeros_like(self.audio); signal[0] = .1
        out = process_graph(signal, graph('diffuser', dict(wet=1, amount=.6)))
        self.assertGreater(float(np.sum(out[RATE//4:] ** 2)), 1e-6)
        self.assertLess(float(np.sum(out ** 2)), .02001)

    def test_environment_and_file_source_ports_and_absolute_alignment(self):
        for kind in ('environment', 'file'):
            settings = graph(kind)
            settings['edges'] = [dict(**{'from': 'fx', 'to': 'o'})]
            if kind == 'file':
                settings['nodes'][1]['assetPath'] = str(self.path)
            validate_graph(settings)
            full = process_graph(self.audio, settings, duration=1)
            part = process_graph(self.audio[:RATE//4], settings, start=.5, duration=1)
            np.testing.assert_allclose(part, full[RATE//2:RATE*3//4], atol=1e-6)
            after = process_graph(self.audio[:RATE//4], settings, start=1.1, duration=1)
            self.assertEqual(float(np.max(abs(after))), 0)
            settings['edges'].append(dict(**{'from': 'i', 'to': 'fx'}))
            with self.assertRaises(ValueError):
                validate_graph(settings)

    def test_duck_key_is_detection_only_and_recovers(self):
        settings = graph('duck', dict(threshold=-40, ratio=10, depth=18, attack=1, release=30))
        settings['nodes'].insert(2, dict(id='detector', type='file', assetPath=str(self.path)))
        settings['edges'].insert(0, dict(**{'from': 'detector', 'to': 'fx', 'port': 'key'}))
        out = process_graph(self.audio, settings)
        self.assertLess(np.sqrt(np.mean(out[RATE//2:]**2)), np.sqrt(np.mean(self.audio**2)) / 5)
        silence = process_graph(self.audio * 0, settings)
        self.assertEqual(float(np.max(abs(silence))), 0)  # Key is never summed.
        settings['edges'].pop(0)
        np.testing.assert_array_equal(process_graph(self.audio, settings), self.audio)

    def test_custom_ir_predelay_and_bundle_roundtrip(self):
        ir = np.zeros((2400, 2), np.float32); ir[100, 0] = 1; ir[300, 1] = .5
        impulse = self.root / 'impulse.wav'; sf.write(impulse, ir, RATE, subtype='FLOAT')
        settings = graph('convolution', dict(wet=1, predelayMs=10, normalize=0))
        settings['nodes'][1]['assetPath'] = str(impulse)
        signal = np.zeros_like(self.audio); signal[0] = 1
        out = process_graph(signal, settings)
        self.assertEqual(np.argmax(abs(out[:, 0])), 580)
        self.assertEqual(np.argmax(abs(out[:, 1])), 780)
        file = self.root / 'portable.orbit'
        save_bundle(dict(duration=1, objects=[dict(id='x', path=str(self.path), nodeGraph=settings)]), file)
        with load_project(file) as project:
            node = project['objects'][0]['nodeGraph']['nodes'][1]
            self.assertTrue(Path(node['assetPath']).is_file())
            np.testing.assert_allclose(process_graph(signal, project['objects'][0]['nodeGraph']), out, atol=1e-7)
        info = execute(dict(action='project.read', path=str(file)))
        self.assertTrue(info['project']['objects'][0]['nodeGraph']['nodes'][1]['assetPath'].startswith('media/'))

    def test_node_assets_cannot_escape_api_workspace(self):
        outside = self.root.parent / 'outside-orbit-test.wav'
        request = dict(action='project.create', output='escape.orbit', scene=dict(objects=[
            dict(id='x', path=str(self.path), nodeGraph=graph('convolution'))]))
        request['scene']['objects'][0]['nodeGraph']['nodes'][1]['assetPath'] = str(outside)
        with self.assertRaisesRegex(ValueError, 'outside'):
            execute(request, Paths(self.root))
        self.assertFalse((self.root / 'escape.orbit').exists())

    def test_decoder_explains_missing_audio_and_preserves_original(self):
        from engine import load_audio
        before = self.path.read_bytes()
        error = subprocess.CalledProcessError(22, ['ffmpeg'], stderr=b'Output file #0 does not contain any stream')
        with patch('engine.sf.read', side_effect=RuntimeError('format')), patch('engine.subprocess.run', side_effect=error):
            with self.assertRaisesRegex(ValueError, '没有可解码的音频流'):
                load_audio(str(self.path))
        self.assertEqual(self.path.read_bytes(), before)

    def test_explicit_hrtf_is_not_double_spatialized(self):
        settings = graph('hrtf', dict(azimuth=90, distance=1, spread=0))
        self.assertTrue(graph_is_binaural(settings))
        outputs = []
        for i, x in enumerate((0, 9)):
            destination = self.root / f'hrtf{i}.wav'
            render(dict(duration=.15, tail=0, protectPeaks=False, objects=[
                dict(path=str(self.path), nodeGraph=settings, x=x, y=1, gain=-9, reverb=0)]), str(destination))
            outputs.append(sf.read(destination)[0])
        np.testing.assert_array_equal(*outputs)
        self.assertGreater(float(np.max(abs(outputs[0][:, 0] - outputs[0][:, 1]))), .001)
        settings['nodes'][1]['bypass'] = True
        self.assertFalse(graph_is_binaural(settings))

    def test_hrtf_in_detector_or_disconnected_branch_does_not_skip_spatializer(self):
        settings = graph('duck')
        settings['nodes'].append(dict(id='h', type='hrtf'))
        settings['edges'] += [dict(**{'from': 'i', 'to': 'h'}), dict(**{'from': 'h', 'to': 'fx', 'port': 'key'})]
        self.assertFalse(graph_is_binaural(settings))
        settings['edges'] = settings['edges'][:-1]
        self.assertFalse(graph_is_binaural(settings))

    def test_master_graph_gain_acts_after_binaural_sum_without_respatializing(self):
        settings = dict(duration=.2, tail=0, protectPeaks=False, masterGain=0,
                        objects=[dict(id='x', path=str(self.path), x=2, y=-1, gain=-6, reverb=0)])
        plain, enhanced = self.root / 'master_plain.wav', self.root / 'master_gain.wav'
        render(settings, str(plain))
        settings['masterGraph'] = graph('gain', dict(gain=6))
        render(settings, str(enhanced))
        a, _ = sf.read(plain); b, _ = sf.read(enhanced)
        np.testing.assert_allclose(b, a * 10**(.3), atol=4e-7)
        self.assertGreater(np.max(abs(a[:, 0] - a[:, 1])), .001)

    def test_master_delay_history_preview_matches_full_render(self):
        source = self.root / 'short_master.wav'
        sf.write(source, self.audio[:RATE//5], RATE, subtype='FLOAT')
        settings = dict(duration=13, tail=0, protectPeaks=False, masterGain=0,
                        masterGraph=graph('echo', dict(delayMs=1000, feedback=.85, wet=1)),
                        objects=[dict(id='x', path=str(source), gain=-6, reverb=0, x=1, y=2)])
        full, part = self.root / 'master_full.wav', self.root / 'master_part.wav'
        render(settings, str(full))
        render(settings, str(part), start=12, seconds=.2)
        a, _ = sf.read(full); b, _ = sf.read(part)
        self.assertEqual(len(b), RATE//5)
        self.assertGreater(np.max(abs(b)), .0001)
        np.testing.assert_allclose(b, a[12*RATE:12*RATE+RATE//5], atol=3e-7)

    def test_master_graph_rejects_independent_inputs_and_survives_cli_bundle_edit(self):
        from project_io import validate
        for kind in ('hrtf', 'file', 'environment'):
            with self.assertRaises(ValueError):
                validate(dict(masterGraph=graph(kind)))
        project = self.root / 'master.orbit'
        execute(dict(action='project.create', output=str(project), scene=dict(duration=1,
                     objects=[dict(id='x', path=str(self.path))])))
        output = self.root / 'master_edited.orbit'
        execute(dict(action='project.edit', path=str(project), output=str(output), operations=[
            dict(op='project', values=dict(masterGraph=graph('compressor', dict(threshold=-12, ratio=3))))]))
        with load_project(output) as data:
            self.assertEqual(data['masterGraph']['nodes'][1]['params']['ratio'], 3)


if __name__ == '__main__':
    unittest.main(verbosity=2)
