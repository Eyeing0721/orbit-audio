import 'dart:math' as math;

import 'audio_graph.dart';
import 'models.dart';

/// Reusable, inspectable arrangement preset. All results are normal editable
/// objects, graph cables and keyframes, not a separate rendering shortcut.
void arrangeRainScene(
  AudioProject project, {
  double arrival = 24,
  double rainGain = -7,
  double intensity = .8,
}) {
  final tracks = project.objects
      .where((o) => !o.mute && o.generator.isEmpty)
      .toList();
  if (tracks.isEmpty) throw const FormatException('先导入音频并拆分，再应用声场预设');
  final vocal = tracks.where((o) => o.kind == 'vocals').firstOrNull;
  final end = tracks.map((o) => o.offset + o.clipDuration).reduce(math.max);
  project.duration = end;
  project.tail = 5;
  project.masterGain = 0;
  project.protectPeaks = true;
  var melody = 0;
  for (final o in tracks) {
    o.linkId = ''; // Each stem gets its own processing, never linked positions.
    o.solo = false;
    o.keyframes.clear();
    o.interpolation = 'smooth';
    o.interpolationByField.clear();
    o.clip.addAll({'fadeIn': .06, 'fadeOut': 1.2});
    o.values.addAll({
      'echo': 0,
      'distortion': 0,
      'decay': 3.8,
      'highpass': 40,
      'lowpass': 18000,
    });
    if (o == vocal) {
      o.nodeGraph = vocalGraph(intensity);
      o.values.addAll({
        'x': 0,
        'y': 7,
        'z': .6,
        'gain': 1,
        'spread': .12,
        'reverb': .3,
      });
      o.keyAt(0);
      o.keyframes.add({
        'time': math.min(arrival, end),
        'x': 0,
        'y': 1.1,
        'z': 0,
        'gain': -.5,
        'spread': .08,
        'reverb': .18 + .14 * intensity,
        'echo': 0,
        'distortion': 0,
      });
    } else {
      final bass = o.kind == 'bass', drums = o.kind == 'drums';
      final side = melody++ % 2 == 0 ? -1.0 : 1.0;
      o.values.addAll({
        'x': bass || drums ? 0 : side * 2.3,
        'y': bass
            ? .9
            : drums
            ? -1.6
            : -2,
        'z': bass
            ? -.2
            : drums
            ? .2
            : .8,
        'gain': bass
            ? -1
            : drums
            ? 0
            : 1.5,
        'spread': bass
            ? .08
            : drums
            ? .8
            : .72,
        'reverb': bass ? .04 : .2 + .17 * intensity,
      });
      o.nodeGraph = bedGraph(intensity, bass: bass, drums: drums);
      o.keyAt(0);
      // Gently breathing width/height, never orbiting around the listener.
      for (double t = 30; t < end; t += 30) {
        o.keyframes.add({
          'time': t,
          'spread': bass ? .08 : .72 + .14 * math.sin(t / 28),
          'z': bass
              ? -.2
              : drums
              ? .2
              : .8 + .18 * math.sin(t / 35),
        });
      }
    }
  }
  for (var i = 0; i < 3; i++) {
    final kind = 'rainScene$i';
    var o = project.objects.where((o) => o.kind == kind).firstOrNull;
    if (o == null) {
      o = SoundObject(
        id: 'rain_${DateTime.now().microsecondsSinceEpoch}_$i',
        name: ['雨夜 · 左后雨幕', '雨夜 · 右后雨幕', '雨夜 · 顶部细雨'][i],
        kind: kind,
        generator: 'rain',
        colorIndex: 3 + i,
        duration: end,
      );
      project.objects.add(o);
    }
    o.duration = end;
    o.mute = o.solo = false;
    o.values.addAll({
      'x': i == 0
          ? -2.5
          : i == 1
          ? 2.5
          : 0,
      'y': -2,
      'z': i == 2 ? 3 : 1.3,
      'gain': 0,
      'spread': .85,
      'reverb': 0,
      'echo': 0,
      'distortion': 0,
    });
    o.keyframes = [
      {'time': 0, 'gain': -60},
      {'time': math.min(3, end / 4), 'gain': 0},
      {'time': math.max(end / 2, end - 4), 'gain': 0},
      {'time': end, 'gain': -60},
    ];
    o.nodeGraph = rainGraph(vocal?.path ?? '', rainGain - (i == 2 ? 6 : 0), i);
  }
}

AudioGraph vocalGraph(double amount) => AudioGraph(
  enabled: true,
  nodes: [
    AudioNode('input', 'input', 0, 160),
    AudioNode(
      'tone',
      'eq',
      260,
      160,
      params: {'low': -1.5, 'mid': 1, 'high': -.7},
    ),
    AudioNode(
      'comp',
      'compressor',
      520,
      80,
      params: {
        'threshold': -21,
        'ratio': 2.5,
        'attack': 18,
        'release': 180,
        'makeup': 1.5,
      },
    ),
    AudioNode(
      'dirt',
      'distortion',
      780,
      80,
      params: {'drive': 5, 'wet': .12 * amount},
    ),
    AudioNode(
      'shift',
      'microshift',
      1040,
      80,
      params: {'cents': 7, 'wet': .14 * amount},
    ),
    AudioNode(
      'cut',
      'filter',
      520,
      300,
      params: {'highpass': 240, 'lowpass': 8500},
    ),
    AudioNode(
      'room',
      'convolution',
      780,
      300,
      params: {'decay': 3.8, 'predelayMs': 32, 'wet': 1},
    ),
    AudioNode(
      'diffuse',
      'diffuser',
      1040,
      300,
      params: {'amount': .58, 'wet': .65},
    ),
    AudioNode(
      'blend',
      'mix',
      1300,
      160,
      params: {'balance': .28 + .12 * amount},
    ),
    AudioNode('output', 'output', 1560, 160),
  ],
  edges: const [
    AudioEdge('input', 'tone'),
    AudioEdge('tone', 'comp'),
    AudioEdge('comp', 'dirt'),
    AudioEdge('dirt', 'shift'),
    AudioEdge('tone', 'cut'),
    AudioEdge('cut', 'room'),
    AudioEdge('room', 'diffuse'),
    AudioEdge('shift', 'blend', 'a'),
    AudioEdge('diffuse', 'blend', 'b'),
    AudioEdge('blend', 'output'),
  ],
);

AudioGraph bedGraph(double amount, {bool bass = false, bool drums = false}) =>
    AudioGraph(
      enabled: true,
      nodes: [
        AudioNode('input', 'input', 0, 100),
        AudioNode(
          'tone',
          'eq',
          260,
          100,
          params: {
            'low': bass ? 1 : -1,
            'mid': bass ? 0 : -1,
            'high': bass ? -3 : -1,
          },
        ),
        AudioNode(
          'fx',
          bass || drums ? 'compressor' : 'chorus',
          520,
          100,
          params: bass || drums
              ? {'threshold': -20, 'ratio': 2, 'attack': 25, 'release': 140}
              : {'rate': .17, 'depthMs': 3, 'wet': .25 * amount},
        ),
        AudioNode('output', 'output', 780, 100),
      ],
      edges: const [
        AudioEdge('input', 'tone'),
        AudioEdge('tone', 'fx'),
        AudioEdge('fx', 'output'),
      ],
    );

AudioGraph rainGraph(String detector, double gain, int layer) => AudioGraph(
  enabled: true,
  nodes: [
    AudioNode(
      'input',
      'input',
      0,
      420,
    ), // Retained graph input; intentionally disconnected.
    AudioNode(
      'rain',
      'environment',
      0,
      60,
      params: {'kind': 0, 'gain': gain, 'seed': 107 + layer * 137.0},
    ),
    AudioNode('voice', 'file', 260, 300, assetPath: detector),
    AudioNode(
      'tone',
      'filter',
      260,
      60,
      params: {
        'highpass': layer == 2 ? 1500 : 550,
        'lowpass': layer == 2 ? 12500 : 9500,
      },
    ),
    AudioNode(
      'duck',
      'duck',
      520,
      100,
      params: {
        'threshold': -33,
        'ratio': 3,
        'depth': 4.5,
        'attack': 25,
        'release': 650,
      },
    ),
    AudioNode(
      'diffuse',
      'diffuser',
      780,
      100,
      params: {'amount': .53, 'wet': .5},
    ),
    AudioNode(
      'space',
      'hrtf',
      1040,
      100,
      params: {
        'azimuth': layer == 0
            ? 135
            : layer == 1
            ? -135
            : 180,
        'elevation': layer == 2 ? 65 : 25,
        'distance': 1.4,
        'spread': .8,
      },
    ),
    AudioNode('output', 'output', 1300, 100),
  ],
  edges: const [
    AudioEdge('rain', 'tone'),
    AudioEdge('tone', 'duck'),
    AudioEdge('voice', 'duck', 'key'),
    AudioEdge('duck', 'diffuse'),
    AudioEdge('diffuse', 'space'),
    AudioEdge('space', 'output'),
  ],
);
