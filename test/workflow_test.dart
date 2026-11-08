import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/audio_graph.dart';
import 'package:orbit_audio/audio_panels.dart';
import 'package:orbit_audio/main.dart';
import 'package:orbit_audio/models.dart';
import 'package:orbit_audio/node_editor.dart';
import 'package:orbit_audio/project_bundle.dart';
import 'package:orbit_audio/scene_view.dart';
import 'package:orbit_audio/studio.dart';
import 'package:orbit_audio/workspace.dart';

import 'editor_features_test.dart' show EditingController;
import 'startup_test.dart' show loadFonts, configureWindow;

EditingController controller() {
  final c = EditingController();
  final object = SoundObject(
    id: 'rain',
    name: '后侧雨幕 · Rain',
    generator: 'rain',
    duration: 8,
    values: {
      'x': -3,
      'y': -2,
      'z': 2,
      'gain': -6,
      'reverb': .2,
      'spread': .6,
      'echo': 0,
      'distortion': 0,
      'lowpass': 18000,
      'highpass': 40,
      'delayMs': 280,
      'feedback': .42,
      'decay': 2.6,
    },
    nodeGraph: AudioGraph.bathroom(),
  );
  c.project.objects.add(object);
  c.selectedId = object.id;
  c.project.duration = 8;
  c.project.tail = 1;
  c.status = '本地引擎就绪 · KEMAR HRTF · 48 kHz';
  return c;
}

Future<void> screenshot(GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('qa/$name${material3 ? '' : '_Classic'}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  Directory('qa').createSync(recursive: true);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  test('graph connections reject cycles transactionally and malformed layout data falls back', () {
    final graph = AudioGraph(enabled: true);
    final before = jsonEncode(graph.toJson());
    expect(graph.connect('gain', 'gain', 'in'), isNotNull);
    expect(jsonEncode(graph.toJson()), before);
    final invalid = graph.toJson();
    (invalid['nodes'] as List).first['type'] = 'not-a-node';
    expect(() => AudioGraph.fromJson(invalid), throwsFormatException);
    final layout = WorkspaceLayout('nodes', {
      'left': 'bad',
      'right': double.nan,
      'bottom': -9,
    });
    expect(layout.left, .18);
    expect(layout.right, .24);
    expect(layout.bottom, .2);
  });

  testWidgets(
    'top workflow tabs switch editors in the same project at all window sizes',
    (tester) async {
      final c = controller();
      configureWindow(tester);
      for (final size in [const Size(1440, 940), const Size(980, 680)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        );
        await tester.pumpAndSettle();
        for (final workflow in workflows.keys) {
          await tester.tap(find.byKey(ValueKey('workflow-$workflow')));
          await tester.pumpAndSettle();
          expect(c.project.workspace['active'], workflow);
          expect(c.project.objects.length, 1);
          expect(c.selectedId, 'rain');
          expect(tester.takeException(), isNull, reason: '$workflow at $size');
          if (workflow == 'nodes') {
            expect(find.byType(NodeEditor), findsOneWidget);
          }
          if (workflow == 'spectrum') {
            expect(find.byType(SpectrumEditor), findsOneWidget);
          }
          if (workflow == 'editing') {
            expect(find.byType(ClipEditor), findsOneWidget);
          }
          if (workflow == 'mixing') {
            expect(find.byType(MixerPanel), findsOneWidget);
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'dock splitters resize, headers swap and per-workflow layouts persist',
    (tester) async {
      final c = controller();
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(home: Studio(controller: c, initializeEngine: false)),
      );
      await tester.pumpAndSettle();
      final left = tester
          .getSize(find.byKey(const ValueKey('dock-left')))
          .width;
      await tester.drag(
        find.byKey(const ValueKey('split-left')),
        const Offset(65, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('dock-left'))).width,
        greaterThan(left + 20),
      );
      final height = tester
          .getSize(find.byKey(const ValueKey('dock-bottom')))
          .height;
      await tester.drag(
        find.byKey(const ValueKey('split-bottom')),
        const Offset(0, -55),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('dock-bottom'))).height,
        greaterThan(height + 20),
      );
      final target = tester.getCenter(find.byKey(const ValueKey('dock-right')));
      final source = tester.getCenter(
        find.byKey(const ValueKey('dock-header-center')),
      );
      await tester.dragFrom(source, target - source);
      await tester.pumpAndSettle();
      final layouts = c.project.workspace['layouts'] as Map;
      expect(layouts['overview']['editors']['right'], 'scene');
      expect(layouts['overview']['editors']['center'], 'properties');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('workflow-editing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workflow-overview')));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byType(SceneView)).dx,
        greaterThan(tester.view.physicalSize.width * .7),
      );
      final restored = AudioProject.fromJson(
        jsonDecode(jsonEncode(c.project.toJson())),
      );
      expect(
        restored.workspace['layouts']['overview']['editors']['right'],
        'scene',
      );
      final narrowTarget = tester.getCenter(
        find.byKey(const ValueKey('dock-left')),
      );
      final sceneHeader = tester.getCenter(
        find.byKey(const ValueKey('dock-header-right')),
      );
      await tester.dragFrom(sceneHeader, narrowTarget - sceneHeader);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('split-left')),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('切换声场视图'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('恢复当前工作区布局'));
      await tester.pumpAndSettle();
      expect(
        (c.project.workspace['layouts']
            as Map)['overview']['editors']['center'],
        'scene',
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'real node socket dragging, movement, parameter sync and delete stay in node context',
    (tester) async {
      final c = controller();
      c.selected!.nodeGraph = AudioGraph(enabled: true);
      c.duplicate(linked: true);
      c.select('rain');
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(home: Studio(controller: c, initializeEngine: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workflow-nodes')));
      await tester.pumpAndSettle();
      final out = tester.getCenter(
        find.byKey(const ValueKey('node-out-input')),
      );
      final input = tester.getCenter(
        find.byKey(const ValueKey('node-in-output-in')),
      );
      await tester.dragFrom(out, input - out);
      await tester.pumpAndSettle();
      expect(
        c.selected!.nodeGraph.edges.any(
          (e) => e.from == 'input' && e.to == 'output',
        ),
        isTrue,
      );
      final header = find.byKey(const ValueKey('node-header-gain'));
      final old = c.selected!.nodeGraph.node('gain')!.x;
      await tester.drag(header, const Offset(28, 18));
      await tester.pumpAndSettle();
      expect(c.selected!.nodeGraph.node('gain')!.x, greaterThan(old));
      expect(c.selectedNodeId, 'gain');
      await tester.tap(find.byKey(const ValueKey('node-param-gain')));
      await tester.pumpAndSettle();
      expect(
        c.project.objects.last.nodeGraph.node('gain')!.value('gain'),
        c.selected!.nodeGraph.node('gain')!.value('gain'),
      );
      await tester.tap(find.byKey(const ValueKey('node-header-gain')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(c.project.objects.length, 2);
      expect(c.selected!.nodeGraph.node('gain'), isNull);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.selected!.nodeGraph.node('gain'), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('clip selection and toggles are non-destructive and linked', (
    tester,
  ) async {
    final c = controller();
    c.duplicate(linked: true);
    c.select('rain');
    configureWindow(tester);
    await tester.pumpWidget(
      OrbitApp(home: Studio(controller: c, initializeEngine: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workflow-editing')));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('clip-waveform')));
    await tester.dragFrom(
      Offset(box.left + box.width * .2, box.center.dy),
      Offset(box.width * .5, 0),
    );
    await tester.pumpAndSettle();
    expect(c.selected!.clip['trimStart'], closeTo(1.6, .2));
    expect(c.selected!.clipDuration, closeTo(4, .2));
    await tester.tap(find.byKey(const ValueKey('clip-normalize')));
    await tester.pumpAndSettle();
    expect(c.project.objects.every((o) => o.clip['normalize'] == true), isTrue);
    expect(c.project.objects.first.duration, 8);
    c.undo();
    await tester.pumpAndSettle();
    expect(c.selected!.clip['normalize'], isNot(true));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'spectrum computes real audio, renders pixels and marks changed parameters stale',
    (tester) async {
      final c = controller();
      configureWindow(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workflow-spectrum')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => c.analyzeSelected(seconds: 2));
      await tester.pumpAndSettle();
      expect(c.analysis, isNotNull);
      expect(c.analysisStale, isFalse);
      await tester.runAsync(
        () => tester
            .state<SpectrumEditorState>(find.byType(SpectrumEditor))
            .imageReady!,
      );
      await tester.pumpAndSettle();
      expect(
        tester.state<SpectrumEditorState>(find.byType(SpectrumEditor)).image,
        isNotNull,
      );
      expect(find.byKey(const ValueKey('spectral-plot')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => screenshot(key, 'ORBIT_0.6_频谱工作流'));
      await tester.tap(find.text('频率曲线'));
      await tester.pumpAndSettle();
      c.updateClip({'fadeIn': .2});
      await tester.pumpAndSettle();
      expect(find.text('参数已改 · 需重新分析'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'captures the real node workspace and saves portable graph/clip/layout demo',
    (tester) async {
      final c = controller();
      configureWindow(tester, const Size(1680, 1000));
      c.duplicate(linked: true);
      c.selected!.translatePosition(6, 0, 0);
      c.project.name = 'ORBIT · 工作流与并联雨幕';
      c.project.workspace = {
        'active': 'nodes',
        'layouts': {'nodes': WorkspaceLayout('nodes').toJson()},
      };
      c.selectedNodeId = 'reverb';
      c.updateClip({'fadeIn': .3, 'fadeOut': 1});
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => screenshot(key, 'ORBIT_0.6_节点工作流'));
      await tester.runAsync(
        () => ProjectBundle.save(
          c.project,
          'qa/ORBIT_0.6_工作流演示.orbit',
          File('assets/kemar.sofa').absolute.path,
        ),
      );
      final temp = Directory.systemTemp.createTempSync(
        'orbit-workflow-roundtrip-',
      );
      try {
        final restored = await tester.runAsync(
          () =>
              ProjectBundle.open('qa/ORBIT_0.6_工作流演示.orbit', temp.path),
        );
        expect(restored!.workspace['active'], 'nodes');
        expect(restored.objects.last.nodeGraph.enabled, isTrue);
        expect(restored.objects.last.clip['fadeIn'], .3);
        expect(restored.objects.first.nodeGraph.edges.length, 6);
      } finally {
        temp.deleteSync(recursive: true);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
