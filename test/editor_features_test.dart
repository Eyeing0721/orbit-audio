import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/curve_editor.dart';
import 'package:orbit_audio/models.dart';
import 'package:orbit_audio/project_bundle.dart';
import 'package:orbit_audio/studio_controller.dart';

class EditingController extends StudioController {
  @override
  void changed() {
    if (selected case final object?) project.syncLinked(object);
    dirty = true;
    refresh();
  }
}

void main() {
  test('linked copies share parameters and effect curves, never coordinates or position curves', () {
    final c = EditingController();
    try {
      final a = SoundObject(id: 'a', name: 'Voice', generator: 'rain');
      a.values.addAll({'x': 1, 'y': 2, 'z': 3});
      a.keyAt(0);
      a.keyAt(10);
      c.project.objects.add(a);
      c.selectedId = a.id;
      c.duplicate(linked: true);
      final b = c.selected!;
      expect(a.linkId, isNotEmpty);
      expect(b.linkId, a.linkId);
      c.moveObject(b.id, 7, 8, 9);
      expect(a.value('x', 0), 1);
      expect(b.value('x', 0), 7);
      c.updateValue('reverb', .8);
      expect(a.value('reverb', 0), .8);
      c.select(a.id);
      c.cursor = 10;
      c.updateValue('gain', -15);
      a.interpolationByField['gain'] = 'bezier';
      a.keyframes.last['gain.inT'] = 7;
      a.keyframes.last['gain.inV'] = -4;
      c.changed();
      expect(b.value('gain', 10), -15);
      expect(b.modeFor('gain'), 'bezier');
      expect(b.keyframes.last['gain.inV'], -4);
      final restored = AudioProject.fromJson(
        jsonDecode(jsonEncode(c.project.toJson())),
      );
      restored.objects.first.values['decay'] = 6;
      restored.syncLinked(restored.objects.first);
      expect(restored.objects.last.values['decay'], 6);
      expect(restored.objects.last.value('x', 0), 7);
      c.unlinkSelected();
      c.updateValue('reverb', .2);
      expect(b.value('reverb', 10), isNot(.2));
    } finally {
      c.dispose();
    }
  });
  test('copy/paste translates the whole position animation to the pointer and z=0; G cancel and duplicate cancel are reversible', () {
    final c = EditingController();
    try {
      final a = SoundObject(id: 'a', name: 'Voice', generator: 'rain');
      a.values.addAll({'x': 2, 'y': 4, 'z': 3});
      a.keyAt(0);
      a.keyAt(10);
      c.project.objects.add(a);
      c.selectedId = a.id;
      c.copySelected();
      c.pasteAt(const Offset(-4, 6));
      final pasted = c.selected!;
      expect(pasted.value('x', 0), -4);
      expect(pasted.value('y', 0), 6);
      expect(pasted.value('z', 0), 0);
      expect(pasted.value('z', 10), 0);
      expect(a.value('z', 0), 3);
      expect(pasted.linkId, isEmpty);
      c.beginMove();
      c.moveObject(pasted.id, 5, 5, 5);
      c.cancelMove();
      expect(c.selected!.value('x', 0), -4);
      c.duplicate(move: true);
      final count = c.project.objects.length;
      expect(c.moving, isTrue);
      c.moveObject(c.selectedId!, 9, 9, 9);
      c.cancelMove();
      expect(c.project.objects.length, count);
      expect(c.selected!.value('x', 0), -4);
      c.undo();
      expect(c.project.objects.length, count - 1);
    } finally {
      c.dispose();
    }
  });
  test(
    'Bezier values and channel edits leave other channel keys unchanged',
    () {
      final object = SoundObject(
        id: 'a',
        name: 'a',
        interpolation: 'linear',
        interpolationByField: {'y': 'bezier'},
        keyframes: [
          {'time': 0, 'y': 0, 'x': 4, 'y.outT': 2, 'y.outV': 8},
          {'time': 10, 'y': 10, 'x': 8, 'y.inT': 8, 'y.inV': 2},
        ],
      );
      expect(object.value('y', 5), closeTo(5, 1e-7));
      expect(object.value('y', 2), greaterThan(2));
      final point = CurvePointEdit.move(
        object,
        'y',
        object.keyframes.first,
        1,
        2,
        30,
      );
      expect(point['time'], 1);
      expect(object.keyframes.first['x'], 4);
      expect(object.value('x', 0), 4);
      expect(object.value('y', 1), 2);
      CurvePointEdit.remove(object, 'y', point);
      expect(object.value('x', 0), 4);
    },
  );
  test('portable .orbit embeds and deduplicates original media and HRTF, reopens after sources disappear, and replaces atomically', () async {
    final folder = await Directory.systemTemp.createTemp('orbit-bundle-test-');
    try {
      final source = File('${folder.path}/音频.wav')
        ..writeAsBytesSync(List.generate(4096, (i) => i % 256));
      final hrtf = File('${folder.path}/耳朵.sofa')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final project = AudioProject()
        ..objects.addAll([
          SoundObject(id: 'a', name: 'a', path: source.path, linkId: 'l'),
          SoundObject(id: 'b', name: 'b', path: source.path, linkId: 'l'),
        ]);
      final destination = '${folder.path}/我的工程.orbit';
      await ProjectBundle.save(project, destination, hrtf.path);
      final zip = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      expect(zip.where((f) => f.name.startsWith('media/')).length, 1);
      expect(zip.findFile('assets/hrtf.sofa'), isNotNull);
      project.name = 'Saved twice';
      await ProjectBundle.save(project, destination, hrtf.path);
      final original = await File(destination).readAsBytes();
      source.deleteSync();
      hrtf.deleteSync();
      final opened = await ProjectBundle.open(
        destination,
        '${folder.path}/cache',
      );
      expect(opened.name, 'Saved twice');
      expect(opened.objects.last.linkId, 'l');
      expect(
        await File(opened.objects.first.path).readAsBytes(),
        List.generate(4096, (i) => i % 256),
      );
      expect(await File(opened.hrtf).readAsBytes(), [1, 2, 3, 4]);
      await expectLater(
        ProjectBundle.save(project, destination, hrtf.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(destination).readAsBytes(), original);
    } finally {
      await folder.delete(recursive: true);
    }
  });
  test(
    'untrusted project archives reject path traversal and external references',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'orbit-bundle-test-',
      );
      try {
        final archive = Archive()
          ..addFile(
            ArchiveFile.string(
              'scene.json',
              '{"bundleVersion":1,"objects":[]}',
            ),
          )
          ..addFile(ArchiveFile.string('../escape.txt', 'no'));
        final file = File('${folder.path}/bad.orbit');
        await file.writeAsBytes(ZipEncoder().encode(archive));
        await expectLater(
          ProjectBundle.open(file.path, '${folder.path}/cache'),
          throwsA(isA<FormatException>()),
        );
        expect(await File('${folder.path}/escape.txt').exists(), isFalse);
      } finally {
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'exports a portable linked rain example without copyrighted audio',
    () async {
      final project = AudioProject()
        ..name = 'ORBIT · 关联雨幕与曲线演示'
        ..duration = 12
        ..tail = 2;
      final source = SoundObject(
        id: 'rain-a',
        name: '雨幕 · 前上方',
        generator: 'rain',
        linkId: 'rain-shared',
        interpolationByField: {'y': 'bezier'},
        keyframes: [
          {'time': 0, 'x': -2, 'y': 6, 'z': 3, 'y.outT': 2, 'y.outV': 6},
          {'time': 10, 'x': -2, 'y': 1.8, 'z': 2.5, 'y.inT': 8, 'y.inV': 1.8},
        ],
      );
      source.values['gain'] = -14;
      final linked =
          SoundObject.fromJson(jsonDecode(jsonEncode(source.toJson())))
            ..id = 'rain-b'
            ..name = '雨幕 · 后侧（关联）';
      linked.translatePosition(5, -5, 0);
      project.objects.addAll([source, linked]);
      project.syncLinked(source);
      await ProjectBundle.save(
        project,
        '../outputs/ORBIT_0.4_关联雨幕演示.orbit',
        'assets/kemar.sofa',
      );
      expect(File('../outputs/ORBIT_0.4_关联雨幕演示.orbit').existsSync(), isTrue);
    },
  );
}
