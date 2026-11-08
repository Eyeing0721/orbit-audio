import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/engine_service.dart';
import 'package:orbit_audio/launch_store.dart';
import 'package:orbit_audio/main.dart';
import 'package:orbit_audio/models.dart';
import 'package:orbit_audio/startup.dart';
import 'package:orbit_audio/studio.dart';
import 'package:orbit_audio/studio_controller.dart';
import 'package:orbit_audio/welcome.dart';

class MemoryLaunchStore extends LaunchStore {
  bool done;
  final bool failWrites;
  int writes = 0;
  MemoryLaunchStore({this.done = false, this.failWrites = false});
  @override
  Future<bool> isComplete() async => done;
  @override
  Future<void> complete() async {
    writes++;
    if (failWrites) throw const FileSystemException('read only');
    done = true;
  }
}

class TestEngine extends EngineService {
  final bool fail;
  TestEngine({this.fail = false});
  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> request, {
    void Function(double, String)? onProgress,
  }) async {
    if (fail) throw Exception('Python unavailable');
    return {'hrtf': true, 'demucs': true};
  }
}

Future<void> loadFonts() async {
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
      await (FontLoader(entry.key)
            ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b))))
          .load();
    }
  }
}

void configureWindow(WidgetTester tester, [Size size = const Size(1440, 940)]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1.25);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File('qa/0.4_$name${material3 ? '' : '_Classic'}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  Directory('qa').createSync(recursive: true);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  test('first-run state persists separately from settings and corrupt state is recoverable', () async {
    final folder = await Directory.systemTemp.createTemp('orbit-launch-test-');
    try {
      final settings = File('${folder.path}/settings.json');
      await settings.writeAsString('{"python":"custom-python"}');
      final store = LaunchStore(directory: folder.path);
      expect(await store.isComplete(), isFalse);
      await store.complete();
      expect(await LaunchStore(directory: folder.path).isComplete(), isTrue);
      expect(await settings.readAsString(), '{"python":"custom-python"}');
      await store.file.writeAsString('bad json');
      expect(await store.isComplete(), isFalse);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('first launch is empty and legacy autosave remains recoverable even without Python', () async {
    final folder = await Directory.systemTemp.createTemp('orbit-session-test-');
    final c = StudioController(
      engine: TestEngine(fail: true),
      workspacePath: folder.path,
    );
    try {
      final old = AudioProject()
        ..objects.add(SoundObject(id: 'old', name: '保留的录音'));
      final file = File('${folder.path}/autosave.orbit.json');
      final original = jsonEncode(old.toJson());
      await file.writeAsString(original);
      await c.initialize(restoreAutosave: false);
      expect(c.project.objects, isEmpty);
      expect(c.selectedId, isNull);
      expect(c.recoveryFile, file.path);
      expect(c.status, contains('引擎需要配置'));
      expect(await file.readAsString(), original);
      await c.restorePreviousSession();
      expect(c.project.objects.single.name, '保留的录音');
      expect(await file.readAsString(), original);
    } finally {
      c.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('new sessions restore independently of engine health and first-run reset archives them', () async {
    final folder = await Directory.systemTemp.createTemp('orbit-session-test-');
    final c = StudioController(
      engine: TestEngine(fail: true),
      workspacePath: folder.path,
    );
    final fresh = StudioController(
      engine: TestEngine(),
      workspacePath: folder.path,
    );
    try {
      final project = AudioProject()
        ..objects.add(SoundObject(id: 'session', name: '我的工程'));
      final file = File('${folder.path}/session.orbit.json');
      final original = jsonEncode(project.toJson());
      await file.writeAsString(original);
      await c.initialize();
      expect(c.project.objects.single.name, '我的工程');
      await fresh.initialize(restoreAutosave: false);
      expect(fresh.project.objects, isEmpty);
      expect(fresh.recoveryFile, isNot(file.path));
      expect(await File(fresh.recoveryFile!).readAsString(), original);
      expect(await file.readAsString(), original);
    } finally {
      c.dispose();
      fresh.dispose();
      await folder.delete(recursive: true);
    }
  });

  test(
    'unreadable sessions are not overwritten by automatic empty-project saves',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'orbit-session-test-',
      );
      final c = StudioController(
        engine: TestEngine(),
        workspacePath: folder.path,
      );
      try {
        final file = File('${folder.path}/session.orbit.json');
        await file.writeAsString('partially recovered project');
        await c.initialize();
        expect(c.status, contains('已暂停自动备份'));
        c.changed();
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        expect(await file.readAsString(), 'partially recovered project');
      } finally {
        c.dispose();
        await folder.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'first launch animates, guides, enters empty studio and does not repeat',
    (tester) async {
      configureWindow(tester);
      final store = MemoryLaunchStore();
      final c = StudioController();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OrbitApp(
            home: StartupGate(
              store: store,
              controller: c,
              initializeEngine: false,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(OrbitSplash), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 850));
      await capture(tester, key, 'ORBIT_首次开屏');
      expect(store.done, isFalse);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(find.byType(OrbitOnboarding), findsOneWidget);
      await capture(tester, key, 'ORBIT_首次引导');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('像摆放对象一样，编排声音。'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('进入空工程'), findsOneWidget);
      expect(store.done, isFalse);
      await tester.tap(find.text('进入空工程'));
      await tester.pumpAndSettle();
      expect(find.byType(Studio), findsOneWidget);
      expect(c.project.objects, isEmpty);
      expect(find.text('从一段声音开始'), findsOneWidget);
      expect(store.done, isTrue);
      await capture(tester, key, 'ORBIT_首次空工程');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        OrbitApp(
          home: StartupGate(
            store: store,
            controller: c,
            initializeEngine: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Studio), findsOneWidget);
      expect(find.byType(OrbitSplash), findsNothing);
      expect(find.byType(OrbitOnboarding), findsNothing);
      expect(store.writes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'skip, persistence failure, help replay and minimum window remain usable',
    (tester) async {
      configureWindow(tester, const Size(980, 680));
      final store = MemoryLaunchStore(failWrites: true);
      final c = StudioController();
      await tester.pumpWidget(
        OrbitApp(
          home: StartupGate(
            store: store,
            controller: c,
            initializeEngine: false,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('跳过开场'));
      await tester.pumpAndSettle();
      expect(find.text('跳过引导'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('跳过引导'));
      await tester.pumpAndSettle();
      expect(find.byType(Studio), findsOneWidget);
      expect(find.textContaining('无法记住引导'), findsOneWidget);
      c.recoveryFile = 'preserved-session.orbit.json';
      c.refresh();
      await tester.pump();
      expect(find.text('恢复上次工程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('快速入门'));
      await tester.pumpAndSettle();
      expect(find.byType(OrbitOnboarding), findsOneWidget);
      await tester.tap(find.text('返回工程'));
      await tester.pumpAndSettle();
      expect(find.byType(OrbitOnboarding), findsNothing);
      expect(find.byType(Studio), findsOneWidget);
      expect(c.project.objects, isEmpty);
      expect(store.writes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'reduced motion bypasses splash animation and early skip is remembered',
    (tester) async {
      configureWindow(tester);
      final store = MemoryLaunchStore();
      final c = StudioController();
      await tester.pumpWidget(
        OrbitApp(
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              size: Size(1440, 940),
            ),
            child: StartupGate(
              store: store,
              controller: c,
              initializeEngine: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OrbitSplash), findsNothing);
      expect(find.byType(OrbitOnboarding), findsOneWidget);
      await tester.tap(find.text('跳过引导'));
      await tester.pumpAndSettle();
      expect(store.done, isTrue);
      expect(c.project.objects, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
