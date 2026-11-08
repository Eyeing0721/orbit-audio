import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';

import 'audio_graph.dart';

const orbitColors = [
  Color(0xFF80ADD5),
  Color(0xFF6BB6AD),
  Color(0xFFD5A477),
  Color(0xFFAA9CC7),
  Color(0xFFC98D9E),
  Color(0xFF939FC6),
];
const automatable = [
  'x',
  'y',
  'z',
  'gain',
  'spread',
  'reverb',
  'echo',
  'distortion',
];
const positionFields = ['x', 'y', 'z'];
bool isPositionKey(String key) =>
    positionFields.any((field) => key == field || key.startsWith('$field.'));

double bezierValue(
  double time,
  Map<String, double> a,
  Map<String, double> b,
  String field,
) {
  final t0 = a['time']!, t3 = b['time']!, v0 = a[field]!, v3 = b[field]!;
  final t1 = (a['$field.outT'] ?? t0 + (t3 - t0) / 3).clamp(t0, t3);
  final t2 = (b['$field.inT'] ?? t3 - (t3 - t0) / 3).clamp(t0, t3);
  final v1 = a['$field.outV'] ?? v0, v2 = b['$field.inV'] ?? v3;
  double cubic(double u, double p0, double p1, double p2, double p3) {
    final v = 1 - u;
    return v * v * v * p0 +
        3 * v * v * u * p1 +
        3 * v * u * u * p2 +
        u * u * u * p3;
  }

  var lo = 0.0, hi = 1.0;
  for (var i = 0; i < 32; i++) {
    final u = (lo + hi) / 2;
    if (cubic(u, t0, t1, t2, t3) < time) {
      lo = u;
    } else {
      hi = u;
    }
  }
  return cubic((lo + hi) / 2, v0, v1, v2, v3);
}

String timecode(double seconds) {
  final ms = (seconds * 1000).round();
  return '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}

class SoundObject {
  String id, name, path, kind;
  int colorIndex;
  double duration, offset;
  bool mute, solo, loop;
  String generator, interpolation, room;
  String linkId;
  Map<String, String> interpolationByField;
  List<double> waveform;
  Map<String, double> values;
  List<Map<String, double>> keyframes;
  Map<String, dynamic> clip;
  AudioGraph nodeGraph;
  SoundObject({
    required this.id,
    required this.name,
    this.path = '',
    this.kind = 'audio',
    this.colorIndex = 0,
    this.duration = 30,
    this.offset = 0,
    this.mute = false,
    this.solo = false,
    this.loop = false,
    this.generator = '',
    this.interpolation = 'smooth',
    this.room = 'bathroom',
    this.linkId = '',
    Map<String, String>? interpolationByField,
    List<double>? waveform,
    Map<String, double>? values,
    List<Map<String, double>>? keyframes,
    Map<String, dynamic>? clip,
    AudioGraph? nodeGraph,
  }) : interpolationByField = interpolationByField ?? {},
       clip = clip ?? {},
       nodeGraph = nodeGraph ?? AudioGraph(),
       waveform = waveform ?? [],
       values =
           values ??
           {
             'x': 0,
             'y': 2,
             'z': 0,
             'gain': -3,
             'spread': .25,
             'reverb': .15,
             'echo': 0,
             'distortion': 0,
             'lowpass': 18000,
             'highpass': 40,
             'delayMs': 280,
             'feedback': .42,
             'decay': 2.6,
           },
       keyframes = keyframes ?? [];
  Color get color => orbitColors[colorIndex % orbitColors.length];
  double get clipDuration {
    final start = (clip['trimStart'] as num? ?? 0).toDouble();
    final end = (clip['trimEnd'] as num? ?? 0).toDouble();
    return math.max(
          0,
          (end == 0 ? duration : math.min(duration, end)) - start,
        ) /
        (clip['speed'] as num? ?? 1);
  }

  String modeFor(String field) => interpolationByField[field] ?? interpolation;
  double value(String field, double time) {
    final points = keyframes.where((k) => k.containsKey(field)).toList()
      ..sort((a, b) => a['time']!.compareTo(b['time']!));
    if (points.isEmpty) return values[field] ?? 0;
    if (time <= points.first['time']!) return points.first[field]!;
    if (time >= points.last['time']!) return points.last[field]!;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      if (time < b['time']!) {
        final mode = modeFor(field);
        if (mode == 'step') return a[field]!;
        if (mode == 'bezier') return bezierValue(time, a, b, field);
        var t = (time - a['time']!) / (b['time']! - a['time']!);
        if (mode == 'smooth') t = t * t * (3 - 2 * t);
        return a[field]! + (b[field]! - a[field]!) * t;
      }
    }
    return points.last[field]!;
  }

  void translatePosition(double dx, double dy, double dz) {
    for (final entry in {'x': dx, 'y': dy, 'z': dz}.entries) {
      values[entry.key] = (values[entry.key] ?? 0) + entry.value;
      for (final key in keyframes) {
        for (final name in [
          entry.key,
          '${entry.key}.inV',
          '${entry.key}.outV',
        ]) {
          if (key.containsKey(name)) key[name] = key[name]! + entry.value;
        }
      }
    }
  }

  void keyAt(double time) {
    final existing = keyframes
        .where((k) => (k['time']! - time).abs() < .025)
        .firstOrNull;
    final key = <String, double>{...?existing, 'time': time};
    for (final field in automatable) {
      key[field] = value(field, time);
    }
    keyframes.removeWhere((k) => (k['time']! - time).abs() < .025);
    keyframes.add(key);
    keyframes.sort((a, b) => a['time']!.compareTo(b['time']!));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'kind': kind,
    'colorIndex': colorIndex,
    'duration': duration,
    'offset': offset,
    'mute': mute,
    'solo': solo,
    'loop': loop,
    'generator': generator,
    'interpolation': interpolation,
    'interpolationByField': interpolationByField,
    'linkId': linkId,
    'room': room,
    'clip': clip,
    'nodeGraph': nodeGraph.toJson(),
    'waveform': waveform,
    'keyframes': keyframes,
    ...values,
  };
  factory SoundObject.fromJson(Map<String, dynamic> j) {
    final o = SoundObject(
      id: j['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      name: j['name'] as String? ?? '声音',
      path: j['path'] as String? ?? '',
      kind: j['kind'] as String? ?? 'audio',
      colorIndex: j['colorIndex'] as int? ?? 0,
      duration: (j['duration'] as num? ?? 30).toDouble(),
      offset: (j['offset'] as num? ?? 0).toDouble(),
      mute: j['mute'] == true,
      solo: j['solo'] == true,
      loop: j['loop'] == true,
      generator: j['generator'] as String? ?? '',
      room: j['room'] as String? ?? 'bathroom',
      clip: Map<String, dynamic>.from(j['clip'] as Map? ?? {}),
      nodeGraph: AudioGraph.fromJson(
        Map<String, dynamic>.from(j['nodeGraph'] as Map? ?? {}),
      ),
      interpolation: j['interpolation'] as String? ?? 'smooth',
      linkId: j['linkId'] as String? ?? '',
      interpolationByField: (j['interpolationByField'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      waveform: (j['waveform'] as List? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      keyframes: (j['keyframes'] as List? ?? [])
          .map(
            (v) => (v as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ),
          )
          .toList(),
    );
    for (final k in o.values.keys.toList()) {
      if (j[k] is num) o.values[k] = (j[k] as num).toDouble();
    }
    return o;
  }
}

class AudioProject {
  String name = '未命名场景', hrtf = '';
  double duration = 30, masterGain = -3, tail = 3;
  bool protectPeaks = true;
  Map<String, double> listener = {'x': 0, 'y': 0, 'z': 0, 'yaw': 0, 'pitch': 0};
  List<SoundObject> objects = [];
  Map<String, dynamic> workspace = {};
  AudioGraph masterGraph = AudioGraph();
  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'name': name,
    'hrtf': hrtf,
    'duration': duration,
    'masterGain': masterGain,
    'masterGraph': masterGraph.toJson(),
    'tail': tail,
    'protectPeaks': protectPeaks,
    'listener': listener,
    'workspace': workspace,
    'objects': objects.map((o) => o.toJson()).toList(),
  };
  factory AudioProject.fromJson(Map<String, dynamic> j) {
    final p = AudioProject();
    p.name = j['name'] as String? ?? '未命名场景';
    p.hrtf = j['hrtf'] as String? ?? '';
    p.duration = (j['duration'] as num? ?? 30).toDouble();
    p.masterGain = (j['masterGain'] as num? ?? -3).toDouble();
    p.masterGraph = AudioGraph.fromJson(
      Map<String, dynamic>.from(j['masterGraph'] as Map? ?? {}),
    );
    if (p.masterGraph.nodes.any((n) => masterExcludedNodes.contains(n.type))) {
      throw const FormatException('主输出节点链不能使用 HRTF 或独立输入节点');
    }
    p.tail = (j['tail'] as num? ?? 3).toDouble();
    p.protectPeaks = j['protectPeaks'] != false;
    p.workspace = Map<String, dynamic>.from(j['workspace'] as Map? ?? {});
    if (j['listener'] is Map) {
      p.listener = (j['listener'] as Map).map(
        (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      );
    }
    p.objects = (j['objects'] as List? ?? [])
        .map((o) => SoundObject.fromJson(Map<String, dynamic>.from(o as Map)))
        .toList();
    return p;
  }
  AudioProject();
  void syncLinked(SoundObject source) {
    if (source.linkId.isEmpty) return;
    for (final target in objects.where(
      (o) => o.id != source.id && o.linkId == source.linkId,
    )) {
      target.path = source.path;
      target.kind = source.kind;
      target.duration = source.duration;
      target.offset = source.offset;
      target.mute = source.mute;
      target.solo = source.solo;
      target.loop = source.loop;
      target.generator = source.generator;
      target.room = source.room;
      target.waveform = List.of(source.waveform);
      target.clip = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(source.clip)),
      );
      target.nodeGraph = AudioGraph.fromJson(source.nodeGraph.toJson());
      for (final entry in source.values.entries.where(
        (e) => !positionFields.contains(e.key),
      )) {
        target.values[entry.key] = entry.value;
      }
      for (final field in automatable.where(
        (f) => !positionFields.contains(f),
      )) {
        target.interpolationByField[field] = source.modeFor(field);
      }
      final merged = <Map<String, double>>[];
      void add(Map<String, double> data) {
        if (data.length <= 1) return;
        final existing = merged
            .where((k) => (k['time']! - data['time']!).abs() < .000001)
            .firstOrNull;
        if (existing == null) {
          merged.add(data);
        } else {
          existing.addAll(data);
        }
      }

      for (final key in target.keyframes) {
        add(
          Map.fromEntries(
            key.entries.where((e) => e.key == 'time' || isPositionKey(e.key)),
          ),
        );
      }
      for (final key in source.keyframes) {
        add(
          Map.fromEntries(
            key.entries.where((e) => e.key == 'time' || !isPositionKey(e.key)),
          ),
        );
      }
      target.keyframes = merged
        ..sort((a, b) => a['time']!.compareTo(b['time']!));
    }
  }

  void updateDuration() {
    duration = objects.fold(
      30.0,
      (v, o) => math.max(v, o.clipDuration + o.offset),
    );
  }
}
