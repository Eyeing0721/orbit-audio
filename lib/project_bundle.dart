import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import 'models.dart';

/// An .orbit is a portable ZIP: scene.json + deduplicated media + measured HRTF.
/// Disk streams and a background isolate keep large stems out of the UI heap.
class ProjectBundle {
  static Future<void> save(
    AudioProject project,
    String path,
    String defaultHrtf,
  ) {
    final data =
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>;
    return Isolate.run(() => _save(data, path, defaultHrtf));
  }

  static Future<AudioProject> open(String path, String cacheDirectory) async {
    final data = await Isolate.run(() => _open(path, cacheDirectory));
    return AudioProject.fromJson(data);
  }

  static Future<void> _save(
    Map<String, dynamic> data,
    String path,
    String defaultHrtf,
  ) async {
    final assets = <String, String>{};
    final canonical = <String, String>{};
    String include(String source, {bool hrtf = false}) {
      final file = File(source);
      if (!file.existsSync()) throw FileSystemException('缺少素材，工程未覆盖', source);
      final resolved = file.resolveSymbolicLinksSync();
      if (canonical.containsKey(resolved)) return canonical[resolved]!;
      final extension = resolved
          .split('.')
          .last
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9]'), '');
      final name = hrtf
          ? 'assets/hrtf.sofa'
          : 'media/${assets.length.toString().padLeft(5, '0')}.${extension.isEmpty ? 'audio' : extension}';
      assets[name] = resolved;
      canonical[resolved] = name;
      return name;
    }

    for (final object in data['objects'] as List) {
      if ((object['generator'] as String? ?? '').isEmpty) {
        object['path'] = include(object['path'] as String? ?? '');
      } else {
        object['path'] = '';
      }
      for (final node in object['nodeGraph']?['nodes'] as List? ?? []) {
        if ((node['assetPath'] as String? ?? '').isNotEmpty) {
          node['assetPath'] = include(node['assetPath'] as String);
        }
      }
    }
    data['hrtf'] = include(
      (data['hrtf'] as String? ?? '').isEmpty
          ? defaultHrtf
          : data['hrtf'] as String,
      hrtf: true,
    );
    data['bundleVersion'] = 1;
    final destination = File(path).absolute;
    destination.parent.createSync(recursive: true);
    final temporary = destination.parent.createTempSync('.orbit-save-');
    final payload = File('${temporary.path}/project.orbit');
    final encoder = ZipFileEncoder();
    try {
      encoder.create(payload.path, level: ZipFileEncoder.store);
      try {
        encoder.addArchiveFile(
          ArchiveFile.string('scene.json', jsonEncode(data)),
        );
        for (final asset in assets.entries) {
          await encoder.addFile(
            File(asset.value),
            asset.key,
            ZipFileEncoder.store,
          );
        }
      } finally {
        await encoder.close();
      }
      // Same-volume replacement: a failed save leaves the previous project intact.
      payload.renameSync(destination.path);
    } finally {
      if (payload.existsSync()) payload.deleteSync();
      temporary.deleteSync();
    }
  }

  static Map<String, dynamic> _open(String path, String cacheDirectory) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > 4096) throw const FormatException('工程素材数量超出安全限制');
      final names = <String>{};
      var total = 0;
      for (final file in archive) {
        final safe =
            file.name == 'scene.json' ||
            file.name == 'assets/hrtf.sofa' ||
            RegExp(r'^media/[a-zA-Z0-9_.-]+$').hasMatch(file.name);
        if (!safe ||
            file.isSymbolicLink ||
            !file.isFile ||
            !names.add(file.name)) {
          throw const FormatException('工程含不安全路径、重复项或链接');
        }
        total += file.size;
        if (total > 32 * 1024 * 1024 * 1024 ||
            (file.name == 'scene.json' && file.size > 16 * 1024 * 1024)) {
          throw const FormatException('工程解包大小超出安全限制');
        }
      }
      final manifest = archive.findFile('scene.json');
      if (manifest == null) throw const FormatException('不是有效的 ORBIT 工程');
      final data =
          jsonDecode(utf8.decode(manifest.content)) as Map<String, dynamic>;
      if (data['bundleVersion'] != 1) throw const FormatException('不支持此工程文件版本');
      final project = AudioProject.fromJson(data);
      String requireAsset(String name, String prefix) {
        if (!name.startsWith(prefix) || !names.contains(name)) {
          throw FormatException('工程缺少内嵌素材：$name');
        }
        return name;
      }

      for (final object in project.objects.where((o) => o.generator.isEmpty)) {
        requireAsset(object.path, 'media/');
      }
      for (final object in project.objects) {
        for (final node in object.nodeGraph.nodes.where(
          (n) => n.assetPath.isNotEmpty,
        )) {
          requireAsset(node.assetPath, 'media/');
        }
      }
      requireAsset(project.hrtf, 'assets/');
      final cache = Directory(cacheDirectory)..createSync(recursive: true);
      final folder = cache.createTempSync('project-');
      for (final file in archive.where((f) => f.name != 'scene.json')) {
        final target = File('${folder.path}/${file.name}');
        target.parent.createSync(recursive: true);
        final output = OutputFileStream(target.path);
        try {
          file.writeContent(output);
        } finally {
          output.closeSync();
        }
      }
      for (final object in project.objects.where((o) => o.generator.isEmpty)) {
        object.path = '${folder.path}/${object.path}';
      }
      for (final object in project.objects) {
        for (final node in object.nodeGraph.nodes.where(
          (n) => n.assetPath.isNotEmpty,
        )) {
          node.assetPath = '${folder.path}/${node.assetPath}';
        }
      }
      project.hrtf = '${folder.path}/${project.hrtf}';
      return project.toJson();
    } finally {
      input.closeSync();
    }
  }
}
