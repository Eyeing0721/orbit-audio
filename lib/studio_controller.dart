import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'engine_service.dart';
import 'models.dart';
import 'preview_player.dart';
import 'audio_formats.dart';
import 'project_bundle.dart';
import 'audio_graph.dart';
import 'rain_scene.dart';

class StudioController extends ChangeNotifier {
  final EngineService engine;
  final String? workspacePath;
  bool _disposed = false;
  bool _autosaveAllowed = true;
  late final PreviewPlayer player;
  AudioProject project = AudioProject();
  String? selectedId, projectFile, recoveryFile;
  Map<String, dynamic>? copiedObject;
  String? selectedNodeId, analysisObjectId, analysisFingerprint;
  Map<String, dynamic>? analysis;
  Map<String, dynamic>? lastRender;
  bool editingMasterGraph = false;
  Offset? pointerWorld;
  bool pointerInViewport = false, moving = false;
  String moveAxis = 'XY';
  String? _moveSnapshot, _moveSelected;
  bool _moveCreatedCopy = false;
  List<String> _moveRedo = [];
  double cursor = 0, progress = 0, previewOffset = 0;
  bool busy = false,
      playing = false,
      autoKey = true,
      dirty = false,
      listenerSelected = false;
  String status = '正在检查音频引擎…', taskMessage = '';
  final undoStack = <String>[], redoStack = <String>[];
  StreamSubscription? positionSub, completeSub;
  Timer? autosaveTimer;
  void Function(String)? onError;
  void refresh() => notifyListeners();
  SoundObject? get selected =>
      project.objects.where((o) => o.id == selectedId).firstOrNull;
  AudioGraph? get activeGraph =>
      editingMasterGraph ? project.masterGraph : selected?.nodeGraph;
  AudioNode? get selectedNode => activeGraph?.node(selectedNodeId);
  void setNodeContext(bool master) {
    editingMasterGraph = master;
    selectedNodeId = null;
    refresh();
  }

  bool get analysisStale =>
      analysisObjectId != selectedId ||
      analysisFingerprint != jsonEncode(selected?.toJson());
  String get workspace =>
      workspacePath ??
      '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}/OrbitAudio';
  StudioController({EngineService? engine, this.workspacePath})
    : engine = engine ?? EngineService() {
    player = PreviewPlayer(this.engine);
    positionSub = player.onPositionChanged.listen((p) {
      if (playing) {
        cursor = (previewOffset + p.inMilliseconds / 1000).clamp(
          0,
          project.duration,
        );
        notifyListeners();
      }
    });
    completeSub = player.onPlayerComplete.listen((_) {
      playing = false;
      notifyListeners();
    });
  }
  Future<void> initialize({bool restoreAutosave = true}) async {
    String? backupWarning;
    try {
      final session = File('$workspace/session.orbit.json');
      final legacy = File('$workspace/autosave.orbit.json');
      if (restoreAutosave && await session.exists()) {
        project = AudioProject.fromJson(
          jsonDecode(await session.readAsString()),
        );
        selectedId = project.objects.firstOrNull?.id;
      } else if (await session.exists()) {
        final backup = File(
          '$workspace/recovery/previous-${DateTime.now().microsecondsSinceEpoch}.orbit.json',
        );
        await backup.parent.create(recursive: true);
        await session.copy(backup.path);
        recoveryFile = backup.path;
      } else if (await legacy.exists()) {
        // Previous releases used this filename. Leave it untouched on upgrade.
        recoveryFile = legacy.path;
      }
    } catch (_) {
      _autosaveAllowed = false;
      backupWarning = '上次工程无法读取或备份，已暂停自动备份；请另存工程。原文件保留';
    }
    try {
      final settings = File('$workspace/settings.json');
      if (await settings.exists()) {
        final j = jsonDecode(await settings.readAsString());
        engine.python = j['python'] ?? engine.python;
        engine.ffmpeg = j['ffmpeg'] ?? engine.ffmpeg;
      }
      await engine.run({'action': 'doctor'});
      status = backupWarning ?? '本地引擎就绪 · KEMAR HRTF · 48 kHz';
    } catch (e) {
      status = '${backupWarning == null ? '' : '$backupWarning · '}引擎需要配置：$e';
    }
    notifyListeners();
  }

  Future<void> restorePreviousSession() async {
    if (busy || recoveryFile == null || project.objects.isNotEmpty) return;
    try {
      final restored = AudioProject.fromJson(
        jsonDecode(await File(recoveryFile!).readAsString()),
      );
      remember();
      project = restored;
      selectedId = project.objects.firstOrNull?.id;
      projectFile = null;
      cursor = 0;
      listenerSelected = false;
      status = '上次工程已恢复；旧备份仍保留';
      changed();
    } catch (e) {
      onError?.call('恢复失败，原备份没有修改：$e');
    }
  }

  void remember() {
    undoStack.add(jsonEncode(project.toJson()));
    if (undoStack.length > 60) undoStack.removeAt(0);
    redoStack.clear();
  }

  void changed() {
    if (selected case final object?) project.syncLinked(object);
    dirty = true;
    notifyListeners();
    autosaveTimer?.cancel();
    if (!_autosaveAllowed) return;
    autosaveTimer = Timer(const Duration(milliseconds: 900), () async {
      try {
        await Directory(workspace).create(recursive: true);
        await File('$workspace/session.orbit.json')
            .writeAsString(jsonEncode(project.toJson()));
      } catch (_) {}
    });
  }

  void undo() {
    if (moving) {
      cancelMove();
      return;
    }
    if (busy || undoStack.isEmpty) return;
    redoStack.add(jsonEncode(project.toJson()));
    project = AudioProject.fromJson(jsonDecode(undoStack.removeLast()));
    if (selected == null) selectedId = project.objects.firstOrNull?.id;
    changed();
  }

  void redo() {
    if (busy || redoStack.isEmpty) return;
    undoStack.add(jsonEncode(project.toJson()));
    project = AudioProject.fromJson(jsonDecode(redoStack.removeLast()));
    if (selected == null) selectedId = project.objects.firstOrNull?.id;
    changed();
  }

  void seek(double time) {
    player.stop();
    playing = false;
    cursor = time;
    notifyListeners();
  }

  void select(String id) {
    if (moving) return;
    selectedId = id;
    selectedNodeId = null;
    listenerSelected = false;
    notifyListeners();
  }

  void updateValue(String field, double value) {
    final obj = selected;
    if (obj == null || busy) return;
    if (autoKey && automatable.contains(field)) {
      var key = obj.keyframes
          .where((k) => (k['time']! - cursor).abs() < .025)
          .firstOrNull;
      if (key == null) {
        key = {'time': cursor};
        obj.keyframes.add(key);
        obj.keyframes.sort((a, b) => a['time']!.compareTo(b['time']!));
      }
      key[field] = value;
    } else {
      obj.values[field] = value;
      if (automatable.contains(field)) {
        for (final key in obj.keyframes) {
          key[field] = value;
        }
      }
    }
    changed();
  }

  void updateClip(
    Map<String, dynamic> values, {
    bool record = true,
    bool reset = false,
  }) {
    final object = selected;
    if (object == null || busy || moving) return;
    if (record) remember();
    if (reset) object.clip.clear();
    object.clip.addAll(values);
    project.duration = math.max(
      project.duration,
      object.offset + object.clipDuration,
    );
    changed();
  }

  void selectNode(String id) {
    selectedNodeId = id;
    refresh();
  }

  void addNode(String type) {
    final graph = activeGraph;
    if (graph == null ||
        busy ||
        !nodeSpecs.containsKey(type) ||
        type == 'input' ||
        type == 'output' ||
        (editingMasterGraph && masterExcludedNodes.contains(type)) ||
        graph.nodes.length >= 64) {
      return;
    }
    remember();
    final id = 'n${DateTime.now().microsecondsSinceEpoch}';
    graph.nodes.add(
      AudioNode(
        id,
        type,
        280 + (graph.nodes.length % 3) * 260,
        300 + (graph.nodes.length ~/ 3) * 130,
      ),
    );
    graph.enabled = true;
    selectedNodeId = id;
    changed();
  }

  void connectNodes(String from, String to, String port) {
    final graph = activeGraph;
    if (graph == null || busy) return;
    final proposal = AudioGraph.fromJson(graph.toJson());
    final error = proposal.connect(from, to, port);
    if (error != null) {
      status = error;
      refresh();
      return;
    }
    remember();
    graph.edges = proposal.edges;
    status = '节点已连接 · 预听/导出时生效';
    changed();
  }

  void disconnectNode(String to, String port) {
    if (activeGraph == null || busy) return;
    remember();
    activeGraph!.edges.removeWhere((e) => e.to == to && e.port == port);
    changed();
  }

  void deleteNode() {
    final node = selectedNode;
    if (node == null || busy || node.type == 'input' || node.type == 'output') {
      return;
    }
    remember();
    activeGraph!.remove(node.id);
    selectedNodeId = null;
    changed();
  }

  void updateNodeParameter(String field, double value) {
    final node = selectedNode;
    if (node == null || busy) return;
    if (node.type == 'filter' && field == 'highpass') {
      value = math.min(value, node.value('lowpass') - 1);
    }
    if (node.type == 'filter' && field == 'lowpass') {
      value = math.max(value, node.value('highpass') + 1);
    }
    node.params[field] = value;
    changed();
  }

  Future<void> analyzeSelected({
    double start = 0,
    double seconds = 12,
    bool processed = true,
    String channel = 'mono',
  }) async {
    final object = selected;
    if (object == null || busy) return;
    final snapshot = object.toJson(), fingerprint = jsonEncode(object.toJson());
    final result = await task({
      'action': 'analyze',
      'object': snapshot,
      'start': start,
      'seconds': seconds,
      'processed': processed,
      'channel': channel,
    }, '分析选中音频 · STFT');
    if (result != null) {
      analysis = result;
      analysisObjectId = object.id;
      analysisFingerprint = fingerprint;
      status =
          '频谱已计算 · ${result['peakDb']} dBFS 采样峰值 · ${result['rmsDb']} dBFS RMS';
      refresh();
    }
  }

  void moveObject(String id, double x, double y, double z) {
    selectedId = id;
    updateValue('x', x);
    updateValue('y', y);
    updateValue('z', z);
  }

  void insertKey() {
    final obj = selected;
    if (obj == null || busy) return;
    remember();
    obj.keyAt(cursor);
    changed();
  }

  void deleteKey() {
    final obj = selected;
    if (obj == null || busy) return;
    remember();
    obj.keyframes.removeWhere((k) => (k['time']! - cursor).abs() < .08);
    changed();
  }

  void retime(String id, int index, double time) {
    final keys = project.objects.firstWhere((o) => o.id == id).keyframes;
    final lower = index > 0 ? keys[index - 1]['time']! + .01 : 0.0;
    final upper = index < keys.length - 1
        ? keys[index + 1]['time']! - .01
        : project.duration;
    keys[index]['time'] = time.clamp(lower, math.max(lower, upper));
    changed();
  }

  Future<Map<String, dynamic>?> task(
    Map<String, dynamic> request,
    String message,
  ) async {
    if (busy) return null;
    await player.stop();
    busy = true;
    playing = false;
    progress = 0;
    taskMessage = message;
    notifyListeners();
    try {
      return await engine.run(
        request,
        onProgress: (p, m) {
          progress = p.clamp(0, 1);
          taskMessage = m;
          notifyListeners();
        },
      );
    } catch (e) {
      onError?.call(
        '$e\n\n${engine.logs.join('\n').split('\n').reversed.take(8).toList().reversed.join('\n')}',
      );
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> importAudio({bool ambienceFile = false}) async {
    if (busy || moving) return;
    final files = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(label: '音频', extensions: audioImportExtensions),
      ],
    );
    for (final file in files) {
      final data = await task({
        'action': 'inspect',
        'path': file.path,
      }, '读取波形 · ${file.name}');
      if (data == null) continue;
      remember();
      final obj = SoundObject(
        id: 'o${DateTime.now().microsecondsSinceEpoch}',
        name: data['name'] as String,
        path: file.path,
        kind: ambienceFile ? 'ambience' : 'audio',
        colorIndex: project.objects.length,
        duration: (data['duration'] as num).toDouble(),
        waveform: (data['waveform'] as List)
            .map((v) => (v as num).toDouble())
            .toList(),
        loop: ambienceFile,
      );
      project.objects.add(obj);
      project.updateDuration();
      selectedId = obj.id;
      listenerSelected = false;
      status = '已导入 ${file.name}';
      changed();
    }
  }

  Future<void> openProject() async {
    if (busy || moving) return;
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'ORBIT 单文件工程 / 旧版工程',
          extensions: ['orbit', 'json'],
        ),
      ],
    );
    if (file == null) return;
    await openProjectPath(file.path);
  }

  Future<void> openProjectPath(String path) async {
    if (busy || moving) return;
    busy = true;
    notifyListeners();
    try {
      final bundle = path.toLowerCase().endsWith('.orbit');
      final p = bundle
          ? await ProjectBundle.open(path, '$workspace/unpacked')
          : AudioProject.fromJson(jsonDecode(await File(path).readAsString()));
      final parent = File(path).parent.path;
      for (final obj in p.objects) {
        if (obj.path.isNotEmpty && !File(obj.path).isAbsolute) {
          obj.path = File('$parent/${obj.path}').absolute.path;
        }
        for (final node in obj.nodeGraph.nodes) {
          if (node.assetPath.isNotEmpty && !File(node.assetPath).isAbsolute) {
            node.assetPath = File('$parent/${node.assetPath}').absolute.path;
          }
        }
      }
      if (p.hrtf.isNotEmpty && !File(p.hrtf).isAbsolute) {
        p.hrtf = File('$parent/${p.hrtf}').absolute.path;
      }
      remember();
      await player.stop();
      project = p;
      projectFile = bundle ? path : null;
      cursor = 0;
      playing = false;
      selectedId = p.objects.firstOrNull?.id;
      dirty = false;
      status = '已打开 ${p.name}';
      notifyListeners();
    } catch (e) {
      onError?.call('工程读取失败：$e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> saveProject({bool saveAs = false}) async {
    if (busy || moving) return;
    String? path = saveAs ? null : projectFile;
    path ??= (await getSaveLocation(
      suggestedName: '${project.name}.orbit',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'ORBIT 单文件工程（含素材）', extensions: ['orbit']),
      ],
    ))?.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.orbit')) path += '.orbit';
    await saveProjectPath(path);
  }

  Future<void> saveProjectPath(String path) async {
    if (busy || moving) return;
    busy = true;
    taskMessage = '保存单文件工程 · 嵌入音频与 HRTF';
    notifyListeners();
    try {
      await ProjectBundle.save(
        project,
        path,
        '${engine.root}/assets/kemar.sofa',
      );
      projectFile = path;
      dirty = false;
      status = '单文件工程已保存 · 所有素材已内嵌';
    } catch (e) {
      onError?.call('保存失败，原工程未覆盖：$e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> preview() async {
    if (playing) {
      await player.stop();
      playing = false;
      notifyListeners();
      return;
    }
    if (busy || project.objects.isEmpty) return;
    if (cursor >= project.duration) cursor = 0;
    final offset = cursor;
    final output =
        '${Directory.systemTemp.path}/orbit_preview_${pid}_${DateTime.now().millisecondsSinceEpoch}.wav';
    final data = await task({
      'action': 'render',
      'project': {...project.toJson(), 'format': 'wav16', 'tail': 0},
      'output': output,
      'start': offset,
      'seconds': 20,
    }, '生成从播放头开始的 20 秒预听');
    if (data == null) return;
    try {
      previewOffset = offset;
      await player.play(output);
      playing = true;
      status = '双耳预听 · 耳机聆听 · 修改后需重新生成';
      notifyListeners();
    } catch (e) {
      onError?.call('播放失败：$e');
    }
  }

  Future<void> renderTo(String format, String path) async {
    lastRender = null;
    String canonical(String value) {
      final f = File(value);
      return (f.existsSync()
              ? f.resolveSymbolicLinksSync()
              : '${f.parent.resolveSymbolicLinksSync()}/${f.uri.pathSegments.last}')
          .replaceAll('\\', '/')
          .toLowerCase();
    }

    final inputs = <String>{
      ?projectFile,
      if (project.hrtf.isNotEmpty) project.hrtf,
      for (final o in project.objects) ...[
        if (o.path.isNotEmpty) o.path,
        for (final n in o.nodeGraph.nodes)
          if (n.assetPath.isNotEmpty) n.assetPath,
      ],
    };
    try {
      final destination = canonical(path);
      if (inputs
          .where((p) => File(p).existsSync())
          .any((p) => canonical(p) == destination)) {
        onError?.call('导出不能覆盖工程、原音频、IR 或侧链素材，请换一个保存位置');
        return;
      }
    } catch (e) {
      onError?.call('无法确认导出位置：$e');
      return;
    }
    final data = await task({
      'action': 'render',
      'project': {...project.toJson(), 'format': format},
      'output': path,
    }, '渲染完整空间音频');
    if (data != null) {
      lastRender = data;
      status = '导出完成 · ${data['peakDb']} dBFS · $path';
      notifyListeners();
    }
  }

  Future<void> separate(String source, String model, Set<String> parts) async {
    final original = project.objects.where((o) => o.path == source).toList();
    final data = await task({
      'action': 'separate',
      'path': source,
      'model': model,
      'parts': parts.toList(),
      'output': '$workspace/stems/${DateTime.now().millisecondsSinceEpoch}',
    }, '正在启动 AI 拆分');
    if (data == null) return;
    remember();
    const labels = {
      'vocals': '人声',
      'drums': '鼓组',
      'bass': '贝斯',
      'guitar': '吉他',
      'piano': '钢琴',
      'other': '其他',
      'instrumental': '伴奏',
    };
    for (final o in original) {
      o.mute = true;
    }
    for (final f in data['files'] as List) {
      final key = f['part'] as String;
      final obj = SoundObject(
        id: 's${DateTime.now().microsecondsSinceEpoch}_${project.objects.length}',
        name: labels[key] ?? key,
        path: f['path'] as String,
        kind: key,
        colorIndex: project.objects.length,
        duration: (f['duration'] as num).toDouble(),
        waveform: (f['waveform'] as List)
            .map((v) => (v as num).toDouble())
            .toList(),
      );
      project.objects.add(obj);
      selectedId = obj.id;
    }
    project.updateDuration();
    status = '拆分完成 · ${parts.length} 个部件';
    changed();
  }

  void addAmbience(String kind) {
    if (busy) return;
    remember();
    const names = {
      'rain': '雨幕',
      'wind': '风声',
      'ocean': '海浪',
      'white': '白噪音',
      'pink': '柔和噪音',
    };
    final obj = SoundObject(
      id: 'a${DateTime.now().microsecondsSinceEpoch}',
      name: names[kind]!,
      kind: 'ambience',
      generator: kind,
      colorIndex: project.objects.length,
      duration: project.duration,
    );
    obj.values.addAll({
      'x': -2.8,
      'y': -2,
      'z': 2.8,
      'gain': -12,
      'spread': .9,
      'reverb': .2,
    });
    project.objects.add(obj);
    selectedId = obj.id;
    listenerSelected = false;
    changed();
  }

  void rename(String name) {
    final obj = selected;
    if (obj == null || name.trim().isEmpty) return;
    remember();
    obj.name = name.trim();
    changed();
  }

  void duplicate({bool linked = false, bool move = false}) {
    final o = selected;
    if (o == null || busy || moving) return;
    remember();
    final copy = SoundObject.fromJson(o.toJson());
    copy.id = 'd${DateTime.now().microsecondsSinceEpoch}';
    copy.name += linked ? ' 关联副本' : ' 副本';
    if (linked) {
      if (o.linkId.isEmpty) {
        o.linkId = 'link${DateTime.now().microsecondsSinceEpoch}';
      }
      copy.linkId = o.linkId;
    } else {
      copy.linkId = '';
    }
    project.objects.add(copy);
    selectedId = copy.id;
    listenerSelected = false;
    if (move) beginMove(alreadyRemembered: true, createdCopy: true);
    changed();
  }

  void copySelected() {
    if (selected == null || busy || moving) return;
    copiedObject = jsonDecode(jsonEncode(selected!.toJson()));
    status = '对象已复制 · V 在声场指针处粘贴，Z=0';
    notifyListeners();
  }

  void pasteAt(Offset position) {
    if (copiedObject == null || busy || moving) return;
    remember();
    final copy = SoundObject.fromJson(jsonDecode(jsonEncode(copiedObject)));
    copy.id = 'p${DateTime.now().microsecondsSinceEpoch}';
    copy.name += ' 粘贴';
    copy.linkId = '';
    copy.translatePosition(
      position.dx - copy.value('x', cursor),
      position.dy - copy.value('y', cursor),
      -copy.value('z', cursor),
    );
    project.objects.add(copy);
    project.duration = math.max(project.duration, copy.duration + copy.offset);
    selectedId = copy.id;
    listenerSelected = false;
    status = '已粘贴到 XY 平面 · Z=0';
    changed();
  }

  void pasteFromPointer() {
    if (!pointerInViewport || pointerWorld == null) {
      status = '请将鼠标放到透视或俯视声场，再按 V；正视射线与 XY 平面平行';
      notifyListeners();
      return;
    }
    pasteAt(pointerWorld!);
  }

  void unlinkSelected() {
    if (selected == null || selected!.linkId.isEmpty || busy || moving) return;
    remember();
    selected!.linkId = '';
    status = '已解除参数关联';
    changed();
  }

  void beginMove({bool alreadyRemembered = false, bool createdCopy = false}) {
    if (selected == null || busy || moving) return;
    _moveRedo = List.of(redoStack);
    if (!alreadyRemembered) remember();
    _moveSnapshot = jsonEncode(project.toJson());
    _moveSelected = selectedId;
    _moveCreatedCopy = createdCopy;
    moveAxis = 'XY';
    moving = true;
    player.stop();
    playing = false;
    status = 'G 移动 · X/Y/Z 限轴 · 左键/Enter 确认 · 右键/Esc 取消移动';
    notifyListeners();
  }

  void confirmMove() {
    if (!moving) return;
    moving = false;
    _moveSnapshot = null;
    status = '移动已确认';
    changed();
  }

  void cancelMove() {
    if (!moving || _moveSnapshot == null) return;
    project = AudioProject.fromJson(jsonDecode(_moveSnapshot!));
    selectedId = _moveSelected;
    if (!_moveCreatedCopy && undoStack.isNotEmpty) {
      undoStack.removeLast();
      redoStack
        ..clear()
        ..addAll(_moveRedo);
    }
    moving = false;
    _moveSnapshot = null;
    status = _moveCreatedCopy ? '移动已取消，副本保留在原处' : '移动已取消';
    changed();
  }

  void constrainMove(String axis) {
    if (moving) {
      moveAxis = axis;
      notifyListeners();
    }
  }

  void deleteObject() {
    final o = selected;
    if (o == null || busy || moving) return;
    remember();
    project.objects.remove(o);
    selectedId = project.objects.firstOrNull?.id;
    changed();
  }

  void preset(String type) {
    final o = selected;
    if (o == null || busy) return;
    remember();
    if (type == 'arrival') {
      o.keyframes.clear();
      o.values.addAll({
        'x': 0,
        'y': 7,
        'z': .3,
        'gain': -3,
        'spread': .7,
        'reverb': .42,
      });
      o.keyAt(0);
      o.keyframes.add({
        'time': math.min(35, project.duration),
        'x': 0,
        'y': 1.2,
        'z': 0,
        'gain': -3,
        'spread': .08,
        'reverb': .22,
        'echo': 0,
        'distortion': .08,
      });
    }
    if (type == 'rear') {
      o.keyframes.clear();
      o.values.addAll({'x': -3, 'y': -3, 'z': .2, 'spread': .7, 'reverb': .3});
    }
    if (type == 'bathroom') {
      o.room = 'bathroom';
      o.values.addAll({
        'reverb': .6,
        'decay': 3.6,
        'echo': .12,
        'delayMs': 85,
        'distortion': .08,
      });
      for (final k in o.keyframes) {
        k['reverb'] = .6;
        k['echo'] = .12;
        k['distortion'] = .08;
      }
    }
    if (type == 'dry') {
      o.values.addAll({'reverb': 0, 'echo': 0, 'distortion': 0});
      for (final k in o.keyframes) {
        k['reverb'] = 0;
        k['echo'] = 0;
        k['distortion'] = 0;
      }
    }
    changed();
  }

  void rainScene({
    double arrival = 24,
    double rainGain = -7,
    double intensity = .8,
  }) {
    if (busy || moving) return;
    if (!project.objects.any((o) => !o.mute && o.generator.isEmpty)) {
      onError?.call('先导入音频并拆分，再应用雨夜声场');
      return;
    }
    remember();
    arrangeRainScene(
      project,
      arrival: arrival,
      rainGain: rainGain,
      intensity: intensity,
    );
    selectedId =
        project.objects
            .where((o) => o.kind == 'vocals' && !o.mute)
            .firstOrNull
            ?.id ??
        selectedId;
    selectedNodeId = null;
    listenerSelected = false;
    cursor = 0;
    status = '雨夜声场已应用 · 所有节点、雨声闪避与动画均可继续编辑';
    changed();
  }

  Future<void> loadDemo() async {
    final file = File('${engine.root}/projects/procedural.orbit.json');
    if (!await file.exists()) {
      onError?.call('示例工程文件未找到');
      return;
    }
    remember();
    project = AudioProject.fromJson(jsonDecode(await file.readAsString()));
    selectedId = project.objects.firstOrNull?.id;
    cursor = 0;
    projectFile = null;
    changed();
  }

  Future<void> collectProject() async {
    if (busy) return;
    final destination = await getDirectoryPath(confirmButtonText: '收集到这里');
    if (destination == null) return;
    final folder = Directory(
      '$destination/ORBIT_${DateTime.now().millisecondsSinceEpoch}',
    );
    await Directory('${folder.path}/media').create(recursive: true);
    final copy = AudioProject.fromJson(
      jsonDecode(jsonEncode(project.toJson())),
    );
    try {
      for (var i = 0; i < copy.objects.length; i++) {
        final o = copy.objects[i];
        if (o.generator.isEmpty && o.path.isNotEmpty) {
          final name = o.path.split(RegExp(r'[/\\]')).last;
          final relative = 'media/${i}_$name';
          await File(o.path).copy('${folder.path}/$relative');
          o.path = relative;
        }
        for (var k = 0; k < o.nodeGraph.nodes.length; k++) {
          final node = o.nodeGraph.nodes[k];
          if (node.assetPath.isEmpty) continue;
          final name = node.assetPath.split(RegExp(r'[/\\]')).last;
          final relative = 'media/${i}_node_${k}_$name';
          await File(node.assetPath).copy('${folder.path}/$relative');
          node.assetPath = relative;
        }
      }
      if (copy.hrtf.isNotEmpty) {
        await File(copy.hrtf).copy('${folder.path}/custom.sofa');
        copy.hrtf = 'custom.sofa';
      }
      await File('${folder.path}/scene.orbit.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(copy.toJson()),
      );
      status = '工程与素材已收集到 ${folder.path}';
      notifyListeners();
    } catch (e) {
      onError?.call('收集工程失败：$e');
    }
  }

  void newProject() {
    if (busy || moving) return;
    remember();
    player.stop();
    playing = false;
    project = AudioProject();
    selectedId = null;
    projectFile = null;
    cursor = 0;
    listenerSelected = false;
    changed();
  }

  Future<void> saveSettings(String python, [String ffmpeg = '']) async {
    engine.python = python.trim();
    engine.ffmpeg = ffmpeg.trim();
    await Directory(workspace).create(recursive: true);
    await File('$workspace/settings.json').writeAsString(
      jsonEncode({'python': engine.python, 'ffmpeg': engine.ffmpeg}),
    );
    status = '引擎设置已保存';
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    engine.cancel();
    autosaveTimer?.cancel();
    positionSub?.cancel();
    completeSub?.cancel();
    player.dispose();
    super.dispose();
  }
}
