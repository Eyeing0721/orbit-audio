import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/main.dart';
import 'package:orbit_audio/models.dart';
import 'package:orbit_audio/studio.dart';
import 'package:orbit_audio/studio_controller.dart';
import 'package:orbit_audio/studio_slider.dart';

class TestController extends StudioController {
  int previewCalls = 0;
  @override
  Future<void> preview() async {
    previewCalls++;
  }

  @override
  void changed() {
    dirty = true;
    refresh();
  }
}

void main() {
  Directory('qa').createSync(recursive: true);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    if (!Platform.isWindows) return;
    for (final entry in {
      'Segoe UI': 'segoeui.ttf',
      'Roboto': 'segoeui.ttf',
      'Microsoft YaHei UI': 'msyh.ttc',
      'Bahnschrift': 'bahnschrift.ttf',
      'Consolas': 'consola.ttf',
    }.entries) {
      final file = File('C:/Windows/Fonts/${entry.value}');
      if (await file.exists()) {
        final font = FontLoader(entry.key)
          ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
        await font.load();
      }
    }
  });
  TestController makeController() {
    final c = TestController();
    final demo = File('projects/procedural.orbit.json');
    if (demo.existsSync()) {
      c.project = AudioProject.fromJson(jsonDecode(demo.readAsStringSync()));
    } else {
      c.project.objects.add(SoundObject(id: 'voice', name: '人声'));
    }
    c.selectedId = c.project.objects.first.id;
    c.status = '本地引擎就绪 · KEMAR HRTF · 48 kHz';
    return c;
  }

  testWidgets(
    'professional dark-grey workbench renders without layout errors at desktop sizes',
    (tester) async {
      final c = makeController();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [
        const Size(1440, 940),
        const Size(1100, 780),
        const Size(980, 680),
      ]) {
        tester.view.physicalSize = size;
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'layout at $size');
        expect(find.text('ORBIT'), findsOneWidget);
        expect(find.byType(StudioSlider), findsWidgets);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'keyboard preview, insert keyframe, editing and undo use the same project',
    (tester) async {
      final c = makeController();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 940);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.binding.setSurfaceSize(const Size(1440, 940));
      await tester.pumpWidget(
        OrbitApp(home: Studio(controller: c, initializeEngine: false)),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.previewCalls, 1);
      c.cursor = 18;
      c.refresh();
      await tester.pump();
      final count = c.selected!.keyframes.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      expect(c.selected!.keyframes.length, count + 1);
      final slider = find.byType(StudioSlider).first;
      await tester.tap(slider);
      await tester.pump();
      expect(tester.takeException(), isNull);
      c.undo();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'continuous parameter changes retain a stable accessible slider node',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var value = .2;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) => Center(
              child: SizedBox(
                width: 250,
                height: 30,
                child: StudioSlider(
                  value: value,
                  min: 0,
                  max: 1,
                  onChanged: (v) => set(() => value = v),
                ),
              ),
            ),
          ),
        ),
      );
      final id = tester.getSemantics(find.byType(StudioSlider)).id;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(StudioSlider)) - const Offset(80, 0),
      );
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump();
        expect(tester.getSemantics(find.byType(StudioSlider)).id, id);
      }
      await gesture.up();
      expect(value, greaterThan(.5));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'export actual widget composition as a reviewable screenshot without opening desktop apps',
    (tester) async {
      final c = makeController();
      c.cursor = 18;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 940);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.binding.setSurfaceSize(const Size(1440, 940));
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final picture = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final output = File(
          material3
              ? 'qa/ORBIT_0.4_工作台.png'
              : 'qa/ORBIT_Classic_Regression.png',
        );
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  if (material3) {
    testWidgets('M3 dialogs fit the minimum desktop window', (tester) async {
      final c = makeController();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(980, 680);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.binding.setSurfaceSize(const Size(980, 680));
      await tester.pumpWidget(
        OrbitApp(home: Studio(controller: c, initializeEngine: false)),
      );
      await tester.pump();
      await tester.tap(find.text('AI 部件拆分'));
      await tester.pumpAndSettle();
      expect(find.text('开始拆分'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('引擎设置'));
      await tester.pumpAndSettle();
      expect(find.text('引擎与工作区'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('渲染音频'));
      await tester.pumpAndSettle();
      expect(find.text('渲染空间音频'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    testWidgets(
      'Material 3 view segments and export dialog preserve working actions',
      (tester) async {
        final c = makeController();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 940);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.binding.setSurfaceSize(const Size(1440, 940));
        await tester.pumpWidget(
          OrbitApp(home: Studio(controller: c, initializeEngine: false)),
        );
        await tester.pump();
        expect(find.text('M3'), findsOneWidget);
        expect(find.byType(SegmentedButton<String>), findsNWidgets(2));
        final before = jsonEncode(c.project.toJson());
        await tester.tap(find.text('俯视'));
        await tester.pumpAndSettle();
        expect(find.text('俯视 · XY 平面'), findsOneWidget);
        await tester.tap(find.text('Z 高度'));
        await tester.pumpAndSettle();
        expect(jsonEncode(c.project.toJson()), before);
        await tester.tap(find.text('渲染音频'));
        await tester.pumpAndSettle();
        expect(find.text('渲染空间音频'), findsOneWidget);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        final theme = Theme.of(tester.element(find.byType(AlertDialog)));
        expect(theme.useMaterial3, isTrue);
        expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
        expect(dialog.actions, isNotEmpty);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
}
