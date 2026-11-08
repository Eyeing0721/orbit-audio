import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/models.dart';
import 'package:orbit_audio/scene_view.dart';
import 'package:orbit_audio/timeline.dart';

void main() {
  test('keyframe smooth, linear and hold match renderer conventions', () {
    final o = SoundObject(id: 'voice', name: '人声');
    o.keyframes = [
      {'time': 0, 'x': -4},
      {'time': 10, 'x': 4},
    ];
    expect(o.value('x', -1), -4);
    expect(o.value('x', 5), 0);
    expect(o.value('x', 11), 4);
    o.interpolation = 'linear';
    expect(o.value('x', 2.5), -2);
    o.interpolation = 'step';
    expect(o.value('x', 9.9), -4);
  });
  test(
    'project save is lossless and duplicate does not share keyframe maps',
    () {
      final p = AudioProject();
      final o = SoundObject(id: 'voice', name: '人声', path: r'D:\音乐.wav');
      o.keyAt(0);
      p.objects.add(o);
      final q = AudioProject.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(q.toJson(), p.toJson());
      q.objects.first.keyframes.first['x'] = 9;
      expect(p.objects.first.keyframes.first['x'], 0);
    },
  );
  test('perspective drag recovers both ground-plane coordinates', () {
    final p = SceneProjection(
      const Size(800, 600),
      42,
      -.48,
      .64,
      'perspective',
    );
    final delta = p.project(2, -3, 0) - p.project(0, 0, 0);
    final inverse = p.unprojectDelta(delta);
    expect(inverse.dx, closeTo(2, 1e-9));
    expect(inverse.dy, closeTo(-3, 1e-9));
  });
  testWidgets(
    'timeline displays object names, accepts scrub and keyframe drag',
    (tester) async {
      final p = AudioProject();
      p.duration = 30;
      p.objects.add(
        SoundObject(
          id: 'voice',
          name: '测试人声',
          duration: 30,
          keyframes: [
            {'time': 10, 'x': 0},
          ],
        ),
      );
      double cursor = 0;
      int edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                height: 205,
                width: 1000,
                child: AudioTimeline(
                  project: p,
                  cursor: cursor,
                  selected: 'voice',
                  onSeek: (t) => setState(() => cursor = t),
                  onSelect: (_) {},
                  onBeginEdit: () => edits++,
                  onRetime: (id, index, t) => setState(
                    () => p.objects.first.keyframes[index]['time'] = t,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('测试人声'), findsOneWidget);
      await tester.tapAt(const Offset(400, 14));
      await tester.pump();
      expect(cursor, greaterThan(0));
      final box = tester.getSize(find.byType(AudioTimeline));
      final keyX = 224 + 10 / 30 * (box.width - 244);
      await tester.dragFrom(Offset(keyX, 53), const Offset(55, 0));
      await tester.pump();
      expect(edits, 1);
      expect(p.objects.first.keyframes.first['time'], greaterThan(10));
    },
  );
}
