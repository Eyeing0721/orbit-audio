import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/curve_editor.dart';
import 'package:orbit_audio/main.dart';
import 'package:orbit_audio/models.dart';
import 'package:orbit_audio/scene_view.dart';
import 'package:orbit_audio/studio.dart';
import 'package:orbit_audio/timeline.dart';

import 'editor_features_test.dart' show EditingController;
import 'startup_test.dart' show loadFonts, configureWindow;

EditingController makeController() {
  final c = EditingController();
  final object = SoundObject(
    id: 'voice',
    name: '人声 · 走近',
    generator: 'rain',
    interpolationByField: {'y': 'bezier'},
    keyframes: [
      {'time': 0, 'x': 0, 'y': 6, 'z': .2},
      {'time': 10, 'x': 1, 'y': 1, 'z': .2},
    ],
  );
  c.project.objects.add(object);
  c.selectedId = object.id;
  return c;
}

void main() {
  Directory('qa').createSync(recursive: true);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  testWidgets(
    'top left menus and mutually exclusive bottom editors work at all desktop sizes',
    (tester) async {
      final c = makeController();
      configureWindow(tester);
      for (final size in [
        const Size(1440, 940),
        const Size(1100, 780),
        const Size(980, 680),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        );
        await tester.pumpAndSettle();
        for (final label in ['文件', '编辑', '视图', '帮助']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.getCenter(find.text('文件')).dx, lessThan(90));
        await tester.tap(find.text('动画曲线'));
        await tester.pumpAndSettle();
        expect(find.byType(CurveEditor), findsOneWidget);
        expect(find.byType(AudioTimeline), findsNothing);
        expect(tester.takeException(), isNull, reason: 'curve layout $size');
        await tester.tap(find.text('关键帧'));
        await tester.pumpAndSettle();
        expect(find.byType(AudioTimeline), findsOneWidget);
        expect(find.byType(CurveEditor), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.text('关联复制（共享声音参数）'), findsOneWidget);
      await tester.tap(find.text('关联复制（共享声音参数）'));
      await tester.pumpAndSettle();
      expect(c.project.objects.length, 2);
      expect(c.selected!.linkId, isNotEmpty);
      await tester.tap(find.text('视图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('底部：动画曲线'));
      await tester.pumpAndSettle();
      expect(find.byType(CurveEditor), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'left selects only; MMB rotates, Shift MMB pans and Alt MMB zooms without moving audio',
    (tester) async {
      final c = makeController();
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(home: Studio(controller: c, initializeEngine: false)),
      );
      await tester.pumpAndSettle();
      final scene = tester.state<SceneViewState>(find.byType(SceneView));
      final origin = tester.getTopLeft(find.byType(SceneView));
      final objectAt = origin + scene.projection.project(0, 6, .2);
      final before = jsonEncode(c.project.toJson());
      final yaw = scene.yaw;
      await tester.dragFrom(objectAt, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(jsonEncode(c.project.toJson()), before);
      expect(scene.yaw, yaw);
      final middle = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      final at =
          origin + Offset(scene.canvas.width * .45, scene.canvas.height * .7);
      await middle.down(at);
      await middle.moveBy(const Offset(30, 14));
      await middle.up();
      await tester.pump();
      expect(scene.yaw, isNot(yaw));
      final rotated = scene.yaw;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await middle.down(at);
      await middle.moveBy(const Offset(28, 18));
      await middle.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(scene.pan, isNot(Offset.zero));
      expect(scene.yaw, rotated);
      final scale = scene.scale;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await middle.down(at);
      await middle.moveBy(const Offset(0, -24));
      await middle.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(scene.scale, greaterThan(scale));
      expect(jsonEncode(c.project.toJson()), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'G modal transform, Shift D, Ctrl D and pointer C/V shortcuts operate on real objects',
    (tester) async {
      final c = makeController();
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(home: Studio(controller: c, initializeEngine: false)),
      );
      await tester.pumpAndSettle();
      final scene = tester.state<SceneViewState>(find.byType(SceneView));
      final origin = tester.getTopLeft(find.byType(SceneView));
      final at =
          origin + Offset(scene.canvas.width * .6, scene.canvas.height * .65);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await mouse.moveTo(at);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pump();
      expect(c.moving, isTrue);
      await mouse.moveTo(at + const Offset(48, 12));
      await tester.pump();
      expect(c.selected!.value('x', c.cursor), isNot(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(c.moving, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(c.project.objects.length, 2);
      expect(c.moving, isTrue);
      await mouse.moveTo(at + const Offset(70, 18));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.moving, isFalse);
      expect(c.project.objects.length, 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.project.objects.length, 3);
      expect(c.selected!.linkId, isNotEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      final pasteAt = at + const Offset(-50, 20);
      await mouse.moveTo(pasteAt);
      await tester.pump();
      final ground = scene.projection.groundAt(pasteAt - origin)!;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(c.project.objects.length, 4);
      expect(c.selected!.value('x', c.cursor), closeTo(ground.dx, 1e-7));
      expect(c.selected!.value('y', c.cursor), closeTo(ground.dy, 1e-7));
      expect(c.selected!.value('z', c.cursor), 0);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'curve key and Bezier handle dragging edit automation and undo; text entry keeps C V G',
    (tester) async {
      final c = makeController();
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(home: Studio(controller: c, initializeEngine: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('动画曲线'));
      await tester.pumpAndSettle();
      final editor = tester.state<CurveEditorState>(find.byType(CurveEditor));
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('curve-canvas')),
      );
      final before = c.selected!.value('y', 5);
      await tester.dragFrom(origin + editor.point(0, 6), const Offset(40, -8));
      await tester.pumpAndSettle();
      expect(
        c.selected!.keyframes.where((k) => k.containsKey('y')).first['time'],
        greaterThan(0),
      );
      final key = editor.selected!;
      final handle = editor.handle(key, false)!;
      await tester.dragFrom(
        origin + editor.point(handle.dx, handle.dy),
        const Offset(18, 20),
      );
      await tester.pumpAndSettle();
      expect(editor.selected!['y.outV'], isNotNull);
      expect(c.selected!.value('y', 5), isNot(before));
      expect(tester.takeException(), isNull);
      c.undo();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('听者 / Listener'));
      await tester.pumpAndSettle();
      final input = find.byType(TextField).first;
      await tester.enterText(input, 'cvg');
      final editable = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      expect(editable.controller.text, 'cvg');
      expect(c.copiedObject, isNull);
      expect(c.moving, isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'renders the actual curve workbench without desktop interaction',
    (tester) async {
      configureWindow(tester);
      final c = makeController();
      final demo = File('projects/procedural.orbit.json');
      if (demo.existsSync()) {
        c.project = AudioProject.fromJson(jsonDecode(demo.readAsStringSync()));
        c.selectedId = c.project.objects.first.id;
        c.selected!.interpolationByField['y'] = 'bezier';
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('动画曲线'));
      await tester.pumpAndSettle();
      final editor = tester.state<CurveEditorState>(find.byType(CurveEditor));
      final first = editor.points.first;
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('curve-canvas')),
      );
      await tester.tapAt(origin + editor.point(first['time']!, first['y']!));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'qa/ORBIT_0.4_曲线编辑器${material3 ? '' : '_Classic'}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        img.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
