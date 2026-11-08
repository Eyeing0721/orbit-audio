import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dialogs.dart';
import 'models.dart';
import 'scene_view.dart';
import 'studio_controller.dart';
import 'timeline.dart';
import 'studio_slider.dart';
import 'studio_style.dart';
import 'welcome.dart';
import 'curve_editor.dart';
import 'editor_shortcuts.dart';
import 'studio_menu.dart';
import 'workspace.dart';
import 'node_editor.dart';
import 'audio_panels.dart';
export 'studio_style.dart';

class Studio extends StatefulWidget {
  final StudioController? controller;
  final bool initializeEngine;
  final bool restoreAutosave;
  const Studio({
    super.key,
    this.controller,
    this.initializeEngine = true,
    this.restoreAutosave = true,
  });
  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> {
  late final StudioController c;
  final sceneKey = GlobalKey<SceneViewState>();
  String get workflow => workflows.containsKey(c.project.workspace['active'])
      ? c.project.workspace['active'] as String
      : 'overview';
  WorkspaceLayout get layout {
    final layouts = c.project.workspace['layouts'];
    return WorkspaceLayout(
      workflow,
      layouts is Map && layouts[workflow] is Map
          ? layouts[workflow] as Map
          : null,
    );
  }

  bool get showCurves => layout.editors['bottom'] == 'curves';
  void saveLayout(WorkspaceLayout value) {
    if (c.project.workspace['layouts'] is! Map) {
      c.project.workspace['layouts'] = <String, dynamic>{};
    }
    (c.project.workspace['layouts'] as Map)[workflow] = value.toJson();
    c.changed();
  }

  void setCurves(bool value) {
    final current = layout;
    current.editors['bottom'] = value ? 'curves' : 'timeline';
    saveLayout(current);
  }

  void switchWorkflow(String id) {
    if (c.moving) return;
    c.pointerInViewport = false;
    c.project.workspace['active'] = id;
    c.changed();
  }

  @override
  void initState() {
    super.initState();
    c = widget.controller ?? StudioController();
    c.onError = (message) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('任务没有完成'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(
                message,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    };
    if (widget.initializeEngine) {
      c.initialize(restoreAutosave: widget.restoreAutosave);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => EditorShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): c.preview,
        const SingleActivator(LogicalKeyboardKey.keyI): c.insertKey,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            c.saveProject,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            c.openProject,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyD, shift: true): () =>
            c.duplicate(move: true),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
            c.duplicate(linked: true),
        const SingleActivator(LogicalKeyboardKey.keyC): c.copySelected,
        const SingleActivator(LogicalKeyboardKey.keyV): c.pasteFromPointer,
        const SingleActivator(LogicalKeyboardKey.keyG): () {
          if (sceneKey.currentState != null) c.beginMove();
        },
        const SingleActivator(LogicalKeyboardKey.enter): c.confirmMove,
        const SingleActivator(LogicalKeyboardKey.escape): c.cancelMove,
        const SingleActivator(LogicalKeyboardKey.keyX): () =>
            c.moving ? c.constrainMove('X') : c.deleteObject(),
        const SingleActivator(LogicalKeyboardKey.keyY): () =>
            c.constrainMove('Y'),
        const SingleActivator(LogicalKeyboardKey.keyZ): () =>
            c.constrainMove('Z'),
        const SingleActivator(LogicalKeyboardKey.delete): c.deleteObject,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            c.newProject,
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            c.importAudio(),
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () =>
            c.saveProject(saveAs: true),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            sceneKey.currentState?.resetView(),
        const SingleActivator(LogicalKeyboardKey.numpad1): () =>
            sceneKey.currentState?.setView('front'),
        const SingleActivator(LogicalKeyboardKey.numpad7): () =>
            sceneKey.currentState?.setView('top'),
        const SingleActivator(LogicalKeyboardKey.numpad3): () =>
            sceneKey.currentState?.setView('right'),
        const SingleActivator(LogicalKeyboardKey.numpadDecimal): () =>
            sceneKey.currentState?.frameSelected(),
        const SingleActivator(LogicalKeyboardKey.f1): showGuide,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 250,
                      child: StudioMenuBar(
                        c: c,
                        onExport: () => exportDialog(context, c),
                        onSeparate: () => separationDialog(context, c),
                        onSettings: () => settingsDialog(context, c),
                        onGuide: showGuide,
                        onAbout: showAbout,
                        onResetView: () => sceneKey.currentState?.resetView(),
                        onFrameSelected: () =>
                            sceneKey.currentState?.frameSelected(),
                        onView: (view) => sceneKey.currentState?.setView(view),
                        onCurves: setCurves,
                      ),
                    ),
                    Expanded(
                      child: WorkflowTabs(
                        selected: workflow,
                        onSelect: switchWorkflow,
                        onReset: () => saveLayout(WorkspaceLayout(workflow)),
                      ),
                    ),
                  ],
                ),
                header(),
                workspaceBar(),
                const SizedBox(height: 4),
                if (c.busy) progressBar(),
                Expanded(
                  child: StudioDock(
                    layout: layout,
                    onChanged: saveLayout,
                    editor: editor,
                    bottom: Column(
                      children: [
                        transport(),
                        Expanded(child: timeline()),
                      ],
                    ),
                  ),
                ),
                statusBar(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget editor(String type) => switch (type) {
    'objects' => objectsPanel(),
    'properties' => IgnorePointer(ignoring: c.moving, child: inspector()),
    'nodes' => NodeEditor(controller: c),
    'nodeProps' => NodeProperties(controller: c),
    'clip' => ClipEditor(controller: c),
    'spectrum' => SpectrumEditor(controller: c),
    'mixer' => MixerPanel(controller: c),
    'assets' || 'export' => WorkflowPage(
      type: type,
      controller: c,
      onSeparate: () => separationDialog(context, c),
      onExport: () => exportDialog(context, c),
    ),
    _ => Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            key: sceneKey,
            project: c.project,
            selectedId: c.selectedId,
            time: c.cursor,
            onSelect: c.select,
            onMove: c.moveObject,
            onBeginEdit: c.remember,
            moving: c.moving,
            moveAxis: c.moveAxis,
            onConfirmMove: c.confirmMove,
            onCancelMove: c.cancelMove,
            onConstrainMove: c.constrainMove,
            onPointerPosition: (world, inside) {
              c.pointerWorld = world;
              c.pointerInViewport = inside;
            },
          ),
        ),
        if (c.project.objects.isEmpty) Center(child: emptyScene()),
      ],
    ),
  };
  Future<void> showAbout() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ORBIT · 快捷键'),
      scrollable: true,
      content: const Text(
        '顶部选项卡切换工作流，共用同一工程。\n拖面板分隔线调整大小；拖标题交换编辑器。\n节点：拖端口连线、右键输入断线、中键平移、滚轮缩放。\n节点参数为静态值；频谱需手动分析选中音频。\n\n'
        '左键选择 · 中键旋转\nShift+中键平移 · Alt+中键缩放\nG 移动 · X/Y/Z 限轴 · Enter/左键确认 · Esc/右键取消移动\nShift+D 独立复制并移动 · Ctrl+D 关联复制\nC 复制 · V 粘贴到声场指针 XY 投影（Z=0）\n空格预听 · I 插帧 · X/Delete 删除\nCtrl+S 单文件工程 · Ctrl+O 打开\n\n曲线编辑器：拖点与贝塞尔手柄；双击插帧；滚轮缩放；中键平移；Home 适配。\n名称、轨道颜色、XYZ 与位置曲线独立；关联对象的声音参数和声音曲线同步。\n\nORBIT · 免费本地空间音频编辑器\n内置 MIT KEMAR · 双耳 HRTF · 非 Dolby Atmos',
        style: TextStyle(fontSize: 12, height: 1.9),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  Widget surface(Widget child) => material3
      ? ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(color: panel, child: child),
        )
      : child;
  Future<void> showGuide() {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: OrbitOnboarding(
          revisiting: true,
          onFinished: () async => Navigator.pop(context),
        ),
      ),
    );
  }

  Widget emptyScene() => LayoutBuilder(
    builder: (context, bounds) => Container(
      constraints: const BoxConstraints(maxWidth: 330),
      padding: EdgeInsets.all(bounds.maxHeight < 350 ? 14 : 22),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: panel.withValues(alpha: .97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: line.withValues(alpha: .6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bounds.maxHeight >= 350) ...[
            const Icon(Icons.spatial_audio_outlined, color: accent, size: 28),
            const SizedBox(height: 12),
          ],
          const Text(
            '从一段声音开始',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '导入音频，声音就会成为可摆放、\n可打关键帧的空间对象。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.8, color: muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: c.busy ? null : c.importAudio,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('选择音频文件'),
          ),
          if (c.recoveryFile != null)
            TextButton(
              onPressed: c.busy ? null : c.restorePreviousSession,
              child: const Text('恢复上次工程'),
            ),
        ],
      ),
    ),
  );
  Widget timeline() => showCurves
      ? CurveEditor(controller: c)
      : AudioTimeline(
          project: c.project,
          cursor: c.cursor,
          selected: c.selectedId,
          onSeek: c.seek,
          onSelect: c.select,
          onBeginEdit: c.remember,
          onRetime: c.retime,
        );
  Widget caption(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: material3 ? 10 : 9,
      color: muted,
      letterSpacing: material3 ? 1.1 : 1.6,
      fontWeight: FontWeight.w600,
    ),
  );
  Widget textAction(String label, IconData icon, VoidCallback action) =>
      TextButton.icon(
        onPressed: c.busy ? null : action,
        icon: Icon(icon, size: 15, color: muted),
        label: Text(label, style: const TextStyle(fontSize: 11, color: white)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
        ),
      );
  Widget header() => Container(
    height: material3 ? 60 : 57,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      color: material3 ? ink : Color(0xFF242528),
      border: material3 ? null : Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        Container(
          width: material3 ? 40 : 29,
          height: material3 ? 40 : 29,
          decoration: BoxDecoration(
            color: material3 ? const Color(0xFF304772) : null,
            border: material3 ? null : Border.all(color: accent, width: 1.2),
            borderRadius: BorderRadius.circular(material3 ? 14 : 30),
          ),
          child: const Icon(
            Icons.spatial_audio_off_outlined,
            color: accent,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'ORBIT',
          style: TextStyle(
            fontFamily: 'Bahnschrift',
            letterSpacing: 3.2,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        if (material3)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF364253),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'M3',
              style: TextStyle(
                color: Color(0xFFDCE4F4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (material3) const SizedBox(width: 8),
        if (MediaQuery.sizeOf(context).width > 1100)
          const Text('空间音频工作室', style: TextStyle(fontSize: 11, color: muted)),
        const SizedBox(width: 22),
        Container(width: 1, height: 20, color: line),
        const SizedBox(width: 12),
        textAction('打开', Icons.folder_open, c.openProject),
        textAction('保存', Icons.save_outlined, c.saveProject),
        PopupMenuButton<String>(
          tooltip: '工程操作',
          icon: const Icon(Icons.more_horiz, size: 17),
          onSelected: (v) {
            if (v == 'new') c.newProject();
            if (v == 'saveas') c.saveProject(saveAs: true);
            if (v == 'collect') c.saveProject(saveAs: true);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: Text('新建场景（旧场景可撤销恢复）')),
            PopupMenuItem(value: 'saveas', child: Text('另存工程')),
            PopupMenuItem(value: 'collect', child: Text('另存单文件工程（含素材）')),
          ],
        ),
        IconButton(
          tooltip: '撤销 Ctrl+Z',
          onPressed: c.undoStack.isEmpty ? null : c.undo,
          icon: const Icon(Icons.undo, size: 17),
        ),
        IconButton(
          tooltip: '重做 Ctrl+Shift+Z',
          onPressed: c.redoStack.isEmpty ? null : c.redo,
          icon: const Icon(Icons.redo, size: 17),
        ),
        const Spacer(),
        if (MediaQuery.sizeOf(context).width > 1180)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(material3 ? 30 : 4),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, size: 6, color: accent),
                SizedBox(width: 6),
                Text(
                  'LOCAL ENGINE',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.3,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: showGuide,
          tooltip: '快速入门',
          icon: const Icon(Icons.help_outline, size: 20),
        ),
        IconButton(
          tooltip: '雨夜沉浸声场',
          onPressed: c.busy ? null : () => rainSceneDialog(context, c),
          icon: const Icon(Icons.thunderstorm_outlined, size: 21),
        ),
        IconButton(
          onPressed: c.busy ? null : () => settingsDialog(context, c),
          tooltip: '引擎设置',
          icon: const Icon(Icons.tune),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: c.busy || c.project.objects.isEmpty
              ? null
              : () => exportDialog(context, c),
          icon: const Icon(Icons.file_upload_outlined, size: 16),
          label: const Text('渲染音频', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: ink,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(material3 ? 28 : 5),
            ),
          ),
        ),
      ],
    ),
  );
  Widget workspaceBar() => Container(
    height: 43,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      color: material3 ? ink : Color(0xFF25262A),
      border: material3 ? null : Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        const Icon(Icons.layers_outlined, size: 15, color: muted),
        const SizedBox(width: 9),
        InkWell(
          onTap: () => projectDialog(context, c),
          child: Text(
            c.project.name,
            style: const TextStyle(fontSize: 12, color: white),
          ),
        ),
        if (c.dirty)
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: Text('●', style: TextStyle(fontSize: 7, color: accent)),
          ),
        const SizedBox(width: 12),
        Text(
          '${c.project.objects.length} OBJECTS',
          style: const TextStyle(fontSize: 9, color: muted, letterSpacing: 1),
        ),
        const Spacer(),
        const Icon(Icons.hearing, size: 14, color: accent),
        const SizedBox(width: 7),
        const Text(
          'KEMAR / BINAURAL',
          style: TextStyle(fontSize: 9, color: accent, letterSpacing: 1),
        ),
        const SizedBox(width: 20),
        const Text('48,000 Hz', style: TextStyle(fontSize: 10, color: muted)),
      ],
    ),
  );
  Widget progressBar() => Container(
    height: 42,
    color: const Color(0xFF2C333C),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Row(
      children: [
        const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            c.taskMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: accent),
          ),
        ),
        SizedBox(
          width: 150,
          child: LinearProgressIndicator(
            value: c.progress > 0 ? c.progress : null,
            minHeight: 3,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          '${(c.progress * 100).round()}%',
          style: const TextStyle(fontSize: 11, color: accent),
        ),
        TextButton(onPressed: c.engine.cancel, child: const Text('取消')),
      ],
    ),
  );
  Widget miniToggle(String text, bool enabled, VoidCallback action) => Tooltip(
    message: text == 'M' ? '静音' : '独奏',
    child: InkWell(
      onTap: c.busy ? null : action,
      child: Container(
        width: 23,
        height: 23,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? accent.withValues(alpha: .19) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 9,
            color: enabled ? accent : const Color(0xFF757A83),
          ),
        ),
      ),
    ),
  );
  Widget objectsPanel() => Material(
    color: panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          child: Row(
            children: [
              caption('声音对象'),
              const Spacer(),
              Text(
                '${c.project.objects.length}',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: OutlinedButton.icon(
            onPressed: c.busy ? null : () => c.importAudio(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('导入音频', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF555B65)),
              foregroundColor: accent,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(material3 ? 24 : 5),
              ),
              backgroundColor: material3 ? const Color(0xFF304772) : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 1, 13, 1),
          child: TextButton.icon(
            onPressed: c.busy ? null : () => separationDialog(context, c),
            icon: const Icon(Icons.call_split, size: 15),
            label: const Text('AI 部件拆分', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: muted,
              minimumSize: const Size(0, 28),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        const Divider(height: 1),
        InkWell(
          onTap: () {
            c.listenerSelected = true;
            c.refresh();
          },
          child: Container(
            height: 34,
            margin: material3
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
                : EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.listenerSelected ? const Color(0xFF364253) : null,
              borderRadius: BorderRadius.circular(material3 ? 28 : 0),
            ),
            child: const Row(
              children: [
                Icon(Icons.headphones, size: 16, color: muted),
                SizedBox(width: 10),
                Text(
                  '听者 / Listener',
                  style: TextStyle(fontSize: 11, color: white),
                ),
                Spacer(),
                Icon(Icons.lock_outline, size: 11, color: muted),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: c.project.objects.length,
            itemBuilder: (context, i) {
              final o = c.project.objects[i];
              final active = o.id == c.selectedId && !c.listenerSelected;
              return InkWell(
                onTap: () => c.select(o.id),
                onDoubleTap: () => renameDialog(context, c),
                child: Container(
                  height: material3 ? 48 : 45,
                  margin: material3
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(material3 ? 0xFF364253 : 0xFF343840)
                        : null,
                    borderRadius: BorderRadius.circular(material3 ? 28 : 0),
                    border: material3
                        ? null
                        : Border(
                            left: BorderSide(
                              width: 2,
                              color: active ? o.color : Colors.transparent,
                            ),
                          ),
                  ),
                  padding: const EdgeInsets.only(left: 14, right: 5),
                  child: Row(
                    children: [
                      Icon(
                        o.generator.isNotEmpty
                            ? Icons.water_drop_outlined
                            : o.kind == 'vocals'
                            ? Icons.mic_none
                            : Icons.graphic_eq,
                        color: o.mute ? muted : o.color,
                        size: 16,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          o.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: o.mute ? muted : white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (o.linkId.isNotEmpty)
                        const Tooltip(
                          message: '关联参数副本',
                          child: Icon(Icons.link, size: 12, color: accent),
                        ),
                      miniToggle('M', o.mute, () {
                        c.select(o.id);
                        c.remember();
                        o.mute = !o.mute;
                        c.changed();
                      }),
                      miniToggle('S', o.solo, () {
                        c.select(o.id);
                        c.remember();
                        o.solo = !o.solo;
                        c.changed();
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (!material3 && MediaQuery.sizeOf(context).height > 790) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 6),
            child: caption('ENVIRONMENT'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 5,
              runSpacing: 3,
              children:
                  {
                        'rain': '雨声',
                        'wind': '风声',
                        'ocean': '海浪',
                        'pink': '柔和噪音',
                        'white': '白噪音',
                      }.entries
                      .map(
                        (e) => ActionChip(
                          label: Text(
                            e.value,
                            style: const TextStyle(fontSize: 10),
                          ),
                          onPressed: c.busy ? null : () => c.addAmbience(e.key),
                          side: const BorderSide(color: line),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: const Color(0xFF2C2E33),
                        ),
                      )
                      .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
            child: TextButton.icon(
              onPressed: c.busy
                  ? null
                  : () => c.importAudio(ambienceFile: true),
              icon: const Icon(Icons.library_music_outlined, size: 13),
              label: const Text('导入环境音素材', style: TextStyle(fontSize: 10)),
              style: TextButton.styleFrom(foregroundColor: muted),
            ),
          ),
        ] else
          PopupMenuButton<String>(
            onSelected: (kind) {
              if (kind == 'file') {
                c.importAudio(ambienceFile: true);
              } else {
                c.addAmbience(kind);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rain', child: Text('添加雨声')),
              PopupMenuItem(value: 'wind', child: Text('添加风声')),
              PopupMenuItem(value: 'ocean', child: Text('添加海浪')),
              PopupMenuItem(value: 'white', child: Text('添加白噪音')),
              PopupMenuItem(value: 'pink', child: Text('添加柔和噪音')),
              PopupMenuItem(value: 'file', child: Text('导入环境音素材')),
            ],
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.water_drop_outlined, size: 14),
                  SizedBox(width: 8),
                  Text('添加环境音', style: TextStyle(fontSize: 11)),
                  Spacer(),
                  Icon(Icons.expand_more, size: 14),
                ],
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: line)),
          ),
          child: InkWell(
            onTap: c.busy ? null : c.loadDemo,
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 13, color: accent),
                SizedBox(width: 8),
                Text(
                  '载入程序化雨夜示例',
                  style: TextStyle(fontSize: 10, color: accent),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 13, color: muted),
      const SizedBox(width: 7),
      Text(
        title,
        style: const TextStyle(
          fontSize: material3 ? 13 : 11,
          fontWeight: FontWeight.w600,
          color: white,
        ),
      ),
      const SizedBox(width: 10),
      if (!material3) const Expanded(child: Divider(height: 1, color: line)),
    ],
  );
  Widget inspector() {
    if (c.listenerSelected) return listenerInspector();
    final o = c.selected;
    return Material(
      color: panel,
      child: Column(
        children: [
          Container(
            height: material3 ? 54 : 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                caption('OBJECT PROPERTIES'),
                const Spacer(),
                if (o != null)
                  PopupMenuButton<String>(
                    tooltip: '对象操作',
                    icon: const Icon(Icons.more_horiz, size: 17),
                    onSelected: (v) {
                      if (v == 'rename') renameDialog(context, c);
                      if (v == 'duplicate') c.duplicate();
                      if (v == 'delete') c.deleteObject();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text('复制对象 Shift+D'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('从场景移除（保留音频文件）'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: o == null
                ? const Center(
                    child: Text(
                      '选择一个声音对象',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  )
                : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 15,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 31,
                                height: 31,
                                decoration: BoxDecoration(
                                  color: o.color.withValues(alpha: .13),
                                  borderRadius: BorderRadius.circular(
                                    material3 ? 12 : 6,
                                  ),
                                ),
                                child: Icon(
                                  o.generator.isNotEmpty
                                      ? Icons.water_drop_outlined
                                      : Icons.graphic_eq,
                                  color: o.color,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      o.generator.isEmpty
                                          ? '${o.linkId.isEmpty ? 'AUDIO OBJECT' : 'LINKED DATA'} · ${timecode(o.duration)}'
                                          : 'PROCEDURAL · ${o.generator.toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 8,
                                        color: muted,
                                        letterSpacing: .5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          sectionTitle('变换', Icons.open_with),
                          field(
                            'x',
                            'X · 左右',
                            -12,
                            12,
                            'm',
                            accent: const Color(0xFFE67B74),
                          ),
                          field(
                            'y',
                            'Y · 前后',
                            -12,
                            12,
                            'm',
                            accent: const Color(0xFF8DC779),
                          ),
                          field(
                            'z',
                            'Z · 高度',
                            -6,
                            12,
                            'm',
                            accent: const Color(0xFF7EAFE8),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: c.busy ? null : c.insertKey,
                                  icon: const Icon(
                                    Icons.diamond_outlined,
                                    size: 12,
                                  ),
                                  label: const Text(
                                    '插入关键帧 I',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: line),
                                    foregroundColor: accent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        material3 ? 24 : 4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Tooltip(
                                message: '移除播放头处关键帧',
                                child: IconButton(
                                  onPressed: c.busy ? null : c.deleteKey,
                                  icon: const Icon(
                                    Icons.key_off_outlined,
                                    size: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          DropdownButtonFormField<String>(
                            initialValue: o.interpolation,
                            key: ValueKey('${o.id}_${o.interpolation}'),
                            isDense: true,
                            style: const TextStyle(
                              fontSize: 11,
                              color: white,
                              fontFamily: 'Segoe UI',
                              fontFamilyFallback: [
                                'Microsoft YaHei UI',
                                'Microsoft YaHei',
                              ],
                            ),
                            decoration: const InputDecoration(
                              labelText: '关键帧插值',
                              labelStyle: TextStyle(fontSize: 11),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'smooth',
                                child: Text('平滑 / Smooth'),
                              ),
                              DropdownMenuItem(
                                value: 'linear',
                                child: Text('线性 / Linear'),
                              ),
                              DropdownMenuItem(
                                value: 'step',
                                child: Text('保持 / Step'),
                              ),
                            ],
                            onChanged: c.busy
                                ? null
                                : (v) {
                                    c.remember();
                                    o.interpolation = v!;
                                    o.interpolationByField.clear();
                                    c.changed();
                                  },
                          ),
                          const SizedBox(height: 20),
                          sectionTitle('声音', Icons.volume_up_outlined),
                          field('gain', '对象增益', -48, 12, 'dB'),
                          field('spread', '声像宽度', 0, 1, '%', percent: true),
                          const SizedBox(height: 15),
                          sectionTitle('音效链', Icons.tune),
                          field('reverb', '空间混响', 0, 1, '%', percent: true),
                          field('decay', '尾音长度', .2, 7, 's'),
                          field('echo', '回声', 0, .9, '%', percent: true),
                          field('delayMs', '回声间隔', 30, 1000, 'ms'),
                          field('feedback', '回声反馈', 0, .8, '%', percent: true),
                          field('distortion', '柔性失真', 0, 1, '%', percent: true),
                          field('highpass', '低切', 20, 1000, 'Hz'),
                          field('lowpass', '高切', 1500, 21000, 'Hz'),
                          const SizedBox(height: 18),
                          sectionTitle('快速预设', Icons.auto_awesome_outlined),
                          Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children:
                                {
                                      'arrival': '远处走近',
                                      'rear': '后侧伴奏',
                                      'bathroom': '瓷砖浴室',
                                      'dry': '干声',
                                    }.entries
                                    .map(
                                      (e) => ActionChip(
                                        label: Text(
                                          e.value,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        onPressed: c.busy
                                            ? null
                                            : () => c.preset(e.key),
                                        side: const BorderSide(color: line),
                                        backgroundColor: const Color(
                                          0xFF2D2F34,
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                          const SizedBox(height: 14),
                          numericOption(
                            '片段起点',
                            o.offset,
                            0,
                            c.project.duration,
                            (v) {
                              c.remember();
                              o.offset = v;
                              c.changed();
                            },
                            unit: 's',
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '循环素材',
                              style: TextStyle(fontSize: 11),
                            ),
                            subtitle: const Text(
                              '延展环境音到工程尾部',
                              style: TextStyle(fontSize: 9, color: muted),
                            ),
                            value: o.loop,
                            onChanged: c.busy
                                ? null
                                : (v) {
                                    c.remember();
                                    o.loop = v;
                                    c.changed();
                                  },
                            dense: true,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            o.generator.isEmpty
                                ? o.path
                                : '本地生成的${o.name}，无需素材库',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF777C86),
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget field(
    String key,
    String label,
    double min,
    double max,
    String unit, {
    bool percent = false,
    Color? accent,
  }) {
    final o = c.selected!;
    final value = automatable.contains(key)
        ? o.value(key, c.cursor)
        : (o.values[key] ?? min);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: accent ?? muted),
              ),
              const Spacer(),
              if (o.keyframes.any((k) => k.containsKey(key)))
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Icon(
                    Icons.diamond,
                    size: 7,
                    color: accent ?? const Color(0xFF80ACD7),
                  ),
                ),
              Text(
                '${(value * (percent ? 100 : 1)).toStringAsFixed(unit == 'Hz' || unit == 'ms' || percent ? 0 : 2)} $unit',
                style: const TextStyle(
                  fontSize: 10,
                  color: white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(
            height: material3 ? 30 : 22,
            child: StudioSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChangeStart: c.busy ? null : (_) => c.remember(),
              onChanged: c.busy ? null : (v) => c.updateValue(key, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget numericOption(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> callback, {
    String unit = '',
  }) => Row(
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: muted)),
      const Spacer(),
      SizedBox(
        width: 95,
        child: TextFormField(
          key: ValueKey('${label}_$value'),
          initialValue: value.toStringAsFixed(1),
          style: const TextStyle(fontSize: 11, color: white),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            suffixText: unit,
            suffixStyle: const TextStyle(fontSize: 10, color: muted),
          ),
          onFieldSubmitted: (s) {
            final n = double.tryParse(s);
            if (n != null) callback(n.clamp(min, max));
          },
        ),
      ),
    ],
  );
  Widget listenerInspector() => Material(
    color: panel,
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            caption('LISTENER & MASTER'),
            const SizedBox(height: 20),
            const Text(
              '听者与输出',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              '场景原点是听者头部。Y 正向为正前方，X 正向为右侧，Z 正向为上方。',
              style: TextStyle(fontSize: 11, color: muted, height: 1.8),
            ),
            const SizedBox(height: 20),
            sectionTitle('头部方向', Icons.headphones),
            for (final (key, label, min, max) in [
              ('yaw', '转头 / Yaw', -180.0, 180.0),
              ('pitch', '抬头 / Pitch', -60.0, 60.0),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                        const Spacer(),
                        Text(
                          '${c.project.listener[key]!.round()}°',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    StudioSlider(
                      value: c.project.listener[key]!.clamp(min, max),
                      min: min,
                      max: max,
                      onChangeStart: (_) => c.remember(),
                      onChanged: (v) {
                        c.project.listener[key] = v;
                        c.changed();
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            sectionTitle('主输出', Icons.equalizer),
            const SizedBox(height: 16),
            numericOption('工程时长', c.project.duration, 1, 36000, (v) {
              c.remember();
              c.project.duration = v;
              c.changed();
            }, unit: 's'),
            const SizedBox(height: 12),
            numericOption('尾音余量', c.project.tail, 0, 10, (v) {
              c.remember();
              c.project.tail = v;
              c.changed();
            }, unit: 's'),
            const SizedBox(height: 12),
            numericOption('主音量', c.project.masterGain, -48, 12, (v) {
              c.remember();
              c.project.masterGain = v;
              c.changed();
            }, unit: 'dB'),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: c.project.protectPeaks,
              onChanged: (v) {
                c.remember();
                c.project.protectPeaks = v;
                c.changed();
              },
              title: const Text('峰值保护', style: TextStyle(fontSize: 12)),
              subtitle: const Text(
                '超限时整体衰减，保留片段动态',
                style: TextStyle(fontSize: 9, color: muted),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => settingsDialog(context, c),
              icon: const Icon(Icons.hearing, size: 15),
              label: const Text(
                '更换 SOFA / 引擎设置',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget transport() => Container(
    height: material3 ? 64 : 52,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      color: material3 ? panel : Color(0xFF2C2E33),
      border: material3
          ? null
          : Border(
              top: BorderSide(color: line),
              bottom: BorderSide(color: line),
            ),
    ),
    child: Row(
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('关键帧')),
            ButtonSegment(value: true, label: Text('动画曲线')),
          ],
          selected: {showCurves},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => setCurves(selection.single),
        ),
        const SizedBox(width: 10),
        IconButton(
          onPressed: c.busy ? null : () => c.seek(0),
          tooltip: '回到开头',
          icon: const Icon(Icons.skip_previous, size: 19),
        ),
        Tooltip(
          message: '生成播放头起 20 秒双耳预听 Space',
          child: FilledButton(
            onPressed: c.busy || c.project.objects.isEmpty ? null : c.preview,
            style: FilledButton.styleFrom(
              minimumSize: const Size(material3 ? 48 : 36, material3 ? 40 : 31),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(material3 ? 24 : 5),
              ),
              backgroundColor: accent,
              foregroundColor: ink,
            ),
            child: Icon(c.playing ? Icons.stop : Icons.play_arrow, size: 21),
          ),
        ),
        const SizedBox(width: 15),
        Text(
          timecode(c.cursor),
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 16,
            color: white,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          '/ ${timecode(c.project.duration)}',
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 10,
            color: muted,
          ),
        ),
        const SizedBox(width: 18),
        if (MediaQuery.sizeOf(context).width > 1180)
          const Text('20s 双耳预听', style: TextStyle(fontSize: 10, color: muted)),
        const Spacer(),
        Tooltip(
          message: '开启：改参数时在播放头自动打帧\n关闭：同一参数整体调整所有关键帧',
          child: FilterChip(
            label: const Text('自动打帧', style: TextStyle(fontSize: 10)),
            avatar: Icon(
              Icons.fiber_manual_record,
              size: 10,
              color: c.autoKey ? const Color(0xFFCC8C78) : muted,
            ),
            selected: c.autoKey,
            onSelected: (v) {
              c.autoKey = v;
              c.refresh();
            },
            side: material3
                ? BorderSide.none
                : BorderSide(color: c.autoKey ? const Color(0xFF6B514A) : line),
            backgroundColor: panel,
            selectedColor: const Color(material3 ? 0xFF593E3A : 0xFF3A3030),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 10),
        TextButton.icon(
          onPressed: c.busy ? null : c.insertKey,
          icon: const Icon(Icons.diamond_outlined, size: 13),
          label: const Text('插入 K 帧', style: TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );
  Widget statusBar() => Container(
    height: 29,
    padding: const EdgeInsets.symmetric(horizontal: 15),
    decoration: const BoxDecoration(
      color: material3 ? ink : Color(0xFF202124),
      border: material3 ? null : Border(top: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        const Icon(Icons.circle, size: 5, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            c.status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: muted),
          ),
        ),
        const Text(
          'G 移动   C/V 复制粘贴   I 插帧   Space 预听',
          style: TextStyle(fontSize: 9, color: Color(0xFF7F858E)),
        ),
        const SizedBox(width: 20),
        const Text(
          material3 ? 'MATERIAL 3 · PREVIEW' : 'FREE / OPEN SOURCE',
          style: TextStyle(
            fontSize: 8,
            letterSpacing: 1.1,
            color: Color(0xFF858B94),
          ),
        ),
      ],
    ),
  );
}
