import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/audio_graph.dart';
import 'package:orbit_audio/dialogs.dart';
import 'package:orbit_audio/main.dart';
import 'package:orbit_audio/models.dart';
import 'package:orbit_audio/node_editor.dart';
import 'package:orbit_audio/project_bundle.dart';
import 'package:orbit_audio/rain_scene.dart';

import 'editor_features_test.dart' show EditingController;
import 'startup_test.dart' show loadFonts, configureWindow;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  testWidgets(
    'master node context is editable without an object and stays separate',
    (tester) async {
      final c = EditingController();
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (context, _) => NodeEditor(controller: c),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑主输出节点'));
      await tester.pumpAndSettle();
      expect(c.editingMasterGraph, isTrue);
      await tester.tap(find.text('添加节点'));
      await tester.pumpAndSettle();
      expect(find.text('HRTF 空间化'), findsNothing);
      await tester.tap(find.text('压缩器'));
      await tester.pumpAndSettle();
      expect(c.project.masterGraph.nodes.length, 4);
      expect(c.project.objects, isEmpty);
      final compressor = c.selectedNode!;
      c.connectNodes('input', compressor.id, 'in');
      c.connectNodes(compressor.id, 'output', 'in');
      c.updateNodeParameter('threshold', -12);
      final copy = AudioProject.fromJson(
        jsonDecode(jsonEncode(c.project.toJson())),
      );
      expect(copy.masterGraph.node(compressor.id)!.value('threshold'), -12);
      c.deleteNode();
      expect(c.project.masterGraph.nodes.length, 3);
      c.undo();
      expect(c.project.masterGraph.nodes.length, 4);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test(
    '19 node definitions have valid defaults and typed detector sockets',
    () {
      expect(nodeSpecs.length, 19);
      for (final type in nodeSpecs.keys) {
        final node = AudioNode('x', type, 0, 0);
        expect(AudioNode.fromJson(node.toJson()).type, type);
        for (final p in node.spec.parameters.entries) {
          expect(node.value(p.key), inInclusiveRange(p.value.min, p.value.max));
        }
      }
      final graph = AudioGraph();
      graph.nodes.add(AudioNode('env', 'environment', 0, 0));
      graph.nodes.add(AudioNode('duck', 'duck', 0, 0));
      expect(graph.connect('input', 'env', 'in'), isNotNull);
      expect(graph.connect('env', 'duck', 'in'), isNull);
      expect(graph.connect('input', 'duck', 'key'), isNull);
      expect(AudioGraph.fromJson(graph.toJson()).error, isNull);
    },
  );

  test('rain arrangement keeps originals and creates editable non-orbiting animation', () {
    final project = AudioProject();
    final original = SoundObject(
      id: 'original',
      name: '原音频',
      mute: true,
      duration: 90,
    );
    project.objects = [
      original,
      for (final kind in [
        'vocals',
        'drums',
        'bass',
        'piano',
        'guitar',
        'other',
      ])
        SoundObject(
          id: kind,
          name: kind,
          kind: kind,
          path: '$kind.wav',
          duration: 90,
        ),
    ];
    arrangeRainScene(project);
    expect(project.objects.length, 10);
    expect(original.mute, isTrue);
    expect(original.nodeGraph.enabled, isFalse);
    final vocal = project.objects[1];
    expect(vocal.value('y', 0), 7);
    expect(vocal.value('y', 25), 1.1);
    expect(vocal.value('x', 60), 0);
    expect(vocal.nodeGraph.nodes.any((n) => n.type == 'convolution'), isTrue);
    for (final obj in project.objects) {
      expect(obj.nodeGraph.error, isNull);
    }
    for (final obj in project.objects.where(
      (o) => o.kind.startsWith('rainScene'),
    )) {
      expect(obj.nodeGraph.node('voice')!.assetPath, 'vocals.wav');
      expect(obj.nodeGraph.node('space')!.type, 'hrtf');
      expect(obj.value('gain', 90), -60);
    }
    arrangeRainScene(project, rainGain: -3);
    expect(project.objects.length, 10);
    expect(project.objects.last.nodeGraph.node('rain')!.value('gain'), -9);
    AudioProject.fromJson(jsonDecode(jsonEncode(project.toJson())));
  });

  testWidgets(
    'rain scene panel applies via a real user-facing button and supports undo',
    (tester) async {
      final c = EditingController();
      c.project.objects.add(
        SoundObject(
          id: 'v',
          name: '人声',
          kind: 'vocals',
          path: 'v.wav',
          duration: 60,
        ),
      );
      c.selectedId = 'v';
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => rainSceneDialog(context, c),
                child: const Text('打开声场'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开声场'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用可编辑声场'));
      await tester.pumpAndSettle();
      expect(c.project.objects.length, 4);
      expect(c.project.objects.first.nodeGraph.nodes.length, 10);
      c.undo();
      expect(c.project.objects.length, 1);
      expect(c.project.objects.first.nodeGraph.enabled, isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'new node properties accept exact numeric entry and typing never deletes nodes',
    (tester) async {
      final c = EditingController();
      final obj = SoundObject(id: 'v', name: '声音');
      obj.nodeGraph.nodes.add(AudioNode('h', 'hrtf', 0, 0));
      c.project.objects.add(obj);
      c.selectedId = 'v';
      c.selectedNodeId = 'h';
      configureWindow(tester);
      await tester.pumpWidget(
        OrbitApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (context, _) =>
                  SizedBox(width: 350, child: NodeProperties(controller: c)),
            ),
          ),
        ),
      );
      final input = find.byType(TextFormField).first;
      await tester.enterText(input, '135');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(obj.nodeGraph.node('h')!.value('azimuth'), 135);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('node IR and sidechain assets survive Flutter single-file packing and Python read', () async {
    final temp = Directory.systemTemp.createTempSync('orbit-node-assets-');
    try {
      final bytes = ByteData(44 + 19200);
      void tag(int offset, String s) {
        for (var i = 0; i < s.length; i++) {
          bytes.setUint8(offset + i, s.codeUnitAt(i));
        }
      }

      tag(0, 'RIFF');
      bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
      tag(8, 'WAVEfmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, 48000, Endian.little);
      bytes.setUint32(28, 96000, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      tag(36, 'data');
      bytes.setUint32(40, 19200, Endian.little);
      final source = File('${temp.path}/source.wav')
        ..writeAsBytesSync(bytes.buffer.asUint8List());
      final project = AudioProject();
      final obj = SoundObject(id: 'x', name: 'test', generator: 'rain');
      obj.nodeGraph.nodes.addAll([
        AudioNode('ir', 'convolution', 0, 0, assetPath: source.path),
        AudioNode('key', 'file', 0, 0, assetPath: source.path),
      ]);
      project.objects.add(obj);
      final file = '${temp.path}/nodes.orbit';
      await ProjectBundle.save(
        project,
        file,
        File('assets/kemar.sofa').absolute.path,
      );
      final loaded = await ProjectBundle.open(file, '${temp.path}/cache');
      final nodes = loaded.objects.first.nodeGraph.nodes;
      expect(nodes[3].assetPath, nodes[4].assetPath);
      expect(
        File(nodes[3].assetPath).readAsBytesSync(),
        bytes.buffer.asUint8List(),
      );
      final info = await Process.run('python', [
        'backend/cli.py',
        'project',
        'info',
        file,
      ]);
      expect(info.exitCode, 0, reason: '${info.stderr}');
      expect('${info.stdout}', contains('assetPath'));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
