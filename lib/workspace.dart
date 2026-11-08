import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'studio_style.dart';

const workflows = <String, (String, String)>{
  'overview': ('总览', 'scene'),
  'assets': ('素材与拆分', 'assets'),
  'editing': ('剪辑', 'clip'),
  'spatial': ('空间', 'scene'),
  'nodes': ('节点', 'nodes'),
  'spectrum': ('频谱', 'spectrum'),
  'mixing': ('混音', 'mixer'),
  'export': ('导出', 'export'),
};
const editorTypes = <String, (String, String, IconData)>{
  'objects': ('声音对象', 'SCENE COLLECTION', Icons.account_tree_outlined),
  'scene': ('三维声场', '3D / SPATIAL', Icons.spatial_audio_outlined),
  'properties': ('对象属性', 'PROPERTIES', Icons.tune),
  'assets': ('素材与拆分', 'MEDIA / SEPARATION', Icons.library_music_outlined),
  'clip': ('音频剪辑', 'AUDIO / CLIP', Icons.audio_file_outlined),
  'nodes': ('音频节点', 'AUDIO / NODES', Icons.schema_outlined),
  'nodeProps': ('节点参数', 'NODE PARAMETERS', Icons.tune),
  'spectrum': ('频谱分析', 'SPECTRAL ANALYSIS', Icons.ssid_chart),
  'mixer': ('调音台', 'MIXER', Icons.equalizer),
  'export': ('渲染输出', 'RENDER / DELIVERY', Icons.file_upload_outlined),
};

class WorkspaceLayout {
  double left, right, bottom;
  Map<String, String> editors;
  static double ratio(dynamic value, double fallback, double min, double max) =>
      value is num && value.isFinite
      ? value.toDouble().clamp(min, max)
      : fallback;
  WorkspaceLayout(String workflow, [Map? json])
    : left = ratio(json?['left'], .18, .12, .34),
      right = ratio(json?['right'], .24, .16, .38),
      bottom = ratio(json?['bottom'], .34, .2, .55),
      editors = {
        'left': 'objects',
        'center': workflows[workflow]?.$2 ?? 'scene',
        'right': workflow == 'nodes' ? 'nodeProps' : 'properties',
        'bottom': 'timeline',
      } {
    final saved = json?['editors'];
    if (saved is Map) {
      for (final slot in ['left', 'center', 'right']) {
        if (editorTypes.containsKey(saved[slot])) {
          editors[slot] = saved[slot] as String;
        }
      }
      if (saved['bottom'] == 'curves') editors['bottom'] = 'curves';
    }
    // A view may occur once only (in particular the keyed 3D view).
    if (editors.values.toSet().length != editors.length) {
      editors = {
        'left': 'objects',
        'center': workflows[workflow]?.$2 ?? 'scene',
        'right': workflow == 'nodes' ? 'nodeProps' : 'properties',
        'bottom': 'timeline',
      };
    }
  }
  void setEditor(String slot, String type) {
    final old = editors[slot]!;
    final other = editors.entries
        .where((e) => e.value == type && e.key != slot)
        .firstOrNull;
    if (other != null) editors[other.key] = old;
    editors[slot] = type;
  }

  void swap(String a, String b) {
    final first = editors[a]!;
    editors[a] = editors[b]!;
    editors[b] = first;
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'right': right,
    'bottom': bottom,
    'editors': editors,
  };
}

class WorkflowTabs extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onReset;
  const WorkflowTabs({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onReset,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in workflows.entries)
                Semantics(
                  selected: entry.key == selected,
                  button: true,
                  child: InkWell(
                    key: ValueKey('workflow-${entry.key}'),
                    onTap: () => onSelect(entry.key),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected == entry.key
                            ? panel
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: selected == entry.key
                                ? accent
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        entry.value.$1,
                        style: TextStyle(
                          fontSize: 11,
                          color: selected == entry.key ? white : muted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      SizedBox(
        width: 32,
        height: 30,
        child: IconButton(
          tooltip: '恢复当前工作区布局',
          onPressed: onReset,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.dashboard_customize_outlined, size: 15),
        ),
      ),
    ],
  );
}

/// Three dock areas and an exclusive timeline/curve region. Splits are live,
/// bounded and persisted per workflow. Headers can swap editors via drag/drop.
class StudioDock extends StatelessWidget {
  final WorkspaceLayout layout;
  final ValueChanged<WorkspaceLayout> onChanged;
  final Widget Function(String type) editor;
  final Widget bottom;
  const StudioDock({
    super.key,
    required this.layout,
    required this.onChanged,
    required this.editor,
    required this.bottom,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = bounds.maxWidth, height = bounds.maxHeight;
      final sideSpace = math.max(0.0, width - 360 - 12);
      final leftMin =
          ['properties', 'nodeProps'].contains(layout.editors['left'])
          ? 260.0
          : 184.0;
      final leftWidth = (width * layout.left)
          .clamp(leftMin, math.max(leftMin, sideSpace - 260))
          .toDouble();
      final rightWidth = (width * layout.right)
          .clamp(260.0, math.max(260.0, sideSpace - leftWidth))
          .toDouble();
      final bottomHeight = (height * layout.bottom)
          .clamp(174.0, math.max(174.0, height - 300))
          .toDouble();
      return Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: leftWidth, child: area('left')),
                split('left', false, (delta) {
                  layout.left = (leftWidth + delta) / width;
                  onChanged(layout);
                }),
                Expanded(child: area('center')),
                split('right', false, (delta) {
                  layout.right = (rightWidth - delta) / width;
                  onChanged(layout);
                }),
                SizedBox(width: rightWidth, child: area('right')),
              ],
            ),
          ),
          split('bottom', true, (delta) {
            layout.bottom = (bottomHeight - delta) / height;
            onChanged(layout);
          }),
          SizedBox(
            height: bottomHeight,
            child: Container(
              key: const ValueKey('dock-bottom'),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: line.withValues(alpha: .55)),
              ),
              clipBehavior: Clip.hardEdge,
              child: bottom,
            ),
          ),
        ],
      );
    },
  );

  Widget split(String id, bool horizontal, ValueChanged<double> change) =>
      Semantics(
        label: '调整$id面板大小',
        child: MouseRegion(
          cursor: horizontal
              ? SystemMouseCursors.resizeRow
              : SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: ValueKey('split-$id'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (event) =>
                change(horizontal ? event.delta.dy : event.delta.dx),
            child: SizedBox(
              width: horizontal ? null : 6,
              height: horizontal ? 6 : null,
              child: Center(
                child: Container(
                  width: horizontal ? 30 : 2,
                  height: horizontal ? 2 : 30,
                  color: line.withValues(alpha: .65),
                ),
              ),
            ),
          ),
        ),
      );

  Widget area(String slot) {
    final type = layout.editors[slot]!, spec = editorTypes[type]!;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != slot,
      onAcceptWithDetails: (details) {
        layout.swap(slot, details.data);
        onChanged(layout);
      },
      builder: (context, incoming, rejected) => Container(
        key: ValueKey('dock-$slot'),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: incoming.isEmpty ? line.withValues(alpha: .55) : accent,
            width: incoming.isEmpty ? 1 : 2,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 27,
              color: const Color(0xFF2C2E33),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: PopupMenuButton<String>(
                      key: ValueKey('editor-menu-$slot'),
                      tooltip: '切换编辑器',
                      padding: EdgeInsets.zero,
                      icon: Icon(spec.$3, size: 15, color: accent),
                      onSelected: (value) {
                        layout.setEditor(slot, value);
                        onChanged(layout);
                      },
                      itemBuilder: (_) => editorTypes.entries
                          .map(
                            (e) => PopupMenuItem(
                              value: e.key,
                              child: Text(
                                e.value.$1,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: Draggable<String>(
                      data: slot,
                      maxSimultaneousDrags: 1,
                      feedback: Material(
                        color: panel,
                        elevation: 8,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            spec.$1,
                            style: const TextStyle(color: accent, fontSize: 12),
                          ),
                        ),
                      ),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Container(
                          key: ValueKey('dock-header-$slot'),
                          alignment: Alignment.centerLeft,
                          color: Colors.transparent,
                          child: Text(
                            spec.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Bahnschrift',
                              fontSize: 9,
                              color: muted,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 7),
                    child: Icon(Icons.drag_indicator, size: 13, color: muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Material(
                color: panel,
                child: KeyedSubtree(key: ValueKey(type), child: editor(type)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
