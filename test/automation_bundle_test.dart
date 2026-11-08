import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_audio/project_bundle.dart';

void main() {
  test(
    'CLI bundles and Flutter bundles round-trip media, linked curves and edits',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'orbit-cli-flutter-',
      );
      final python = Platform.environment['ORBIT_PYTHON'] ?? 'python';
      final cli = File('backend/cli.py').absolute.path;
      Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
        final process = await Process.start(python, [cli, 'run', '-']);
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();
        process.stdin.writeln(jsonEncode(request));
        await process.stdin.close();
        final code = await process.exitCode;
        final result = await output;
        expect(code, 0, reason: await errors);
        return (jsonDecode(result) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
      }

      try {
        final wav = ByteData(44 + 9600);
        void tag(int offset, String text) {
          for (var i = 0; i < text.length; i++) {
            wav.setUint8(offset + i, text.codeUnitAt(i));
          }
        }

        tag(0, 'RIFF');
        wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
        tag(8, 'WAVEfmt ');
        wav.setUint32(16, 16, Endian.little);
        wav.setUint16(20, 1, Endian.little);
        wav.setUint16(22, 1, Endian.little);
        wav.setUint32(24, 48000, Endian.little);
        wav.setUint32(28, 96000, Endian.little);
        wav.setUint16(32, 2, Endian.little);
        wav.setUint16(34, 16, Endian.little);
        tag(36, 'data');
        wav.setUint32(40, 9600, Endian.little);
        final source = File('${temporary.path}/中文音源.wav')
          ..writeAsBytesSync(wav.buffer.asUint8List());
        final file = '${temporary.path}/CLI.orbit';
        await call({
          'action': 'project.create',
          'output': file,
          'scene': {
            'name': '命令行互通',
            'duration': 1,
            'objects': [
              for (final id in ['a', 'b'])
                {
                  'id': id,
                  'path': source.path,
                  'name': id,
                  'linkId': 'shared',
                  'x': id == 'a' ? -2 : 2,
                  'interpolationByField': {'y': 'bezier'},
                  'keyframes': [
                    {
                      'time': 0,
                      'y': 8,
                      'y.outT': .3,
                      'y.outV': 7,
                      'reverb': .4,
                    },
                    {'time': 1, 'y': 2, 'y.inT': .8, 'y.inV': 3, 'reverb': .7},
                  ],
                },
            ],
          },
        });
        source.deleteSync(); // Only the generated synthetic fixture is removed.
        final project = await ProjectBundle.open(
          file,
          '${temporary.path}/unpacked',
        );
        expect(project.name, '命令行互通');
        expect(project.objects.first.path, project.objects.last.path);
        expect(
          File(project.objects.first.path).readAsBytesSync(),
          wav.buffer.asUint8List(),
        );
        expect(project.objects.first.modeFor('y'), 'bezier');
        expect(project.objects.first.value('y', .5), inExclusiveRange(2, 8));
        project.objects.first.values['distortion'] = .5;
        project.syncLinked(project.objects.first);
        expect(project.objects.last.values['distortion'], .5);
        expect(project.objects.last.values['x'], 2);
        final guiFile = '${temporary.path}/Flutter.orbit';
        await ProjectBundle.save(
          project,
          guiFile,
          File('assets/kemar.sofa').absolute.path,
        );
        final info = await call({'action': 'project.read', 'path': guiFile});
        final objects = (info['project'] as Map)['objects'] as List;
        expect(objects.last['distortion'], .5);
        expect(objects.last['keyframes'].first['y.outV'], 7);
        await call({
          'action': 'project.edit',
          'path': guiFile,
          'overwrite': true,
          'operations': [
            {
              'op': 'set',
              'id': 'b',
              'values': {'gain': -15, 'z': 2},
            },
          ],
        });
        final edited = await ProjectBundle.open(
          guiFile,
          '${temporary.path}/reopen',
        );
        expect(edited.objects.first.values['gain'], -15);
        expect(edited.objects.first.values['z'], 0);
        expect(edited.objects.last.values['z'], 2);
      } finally {
        temporary.deleteSync(recursive: true);
      }
    },
  );
}
