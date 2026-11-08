import 'package:flutter/material.dart';

import 'studio_controller.dart';
import 'studio_style.dart';

class StudioMenuBar extends StatelessWidget {
  final StudioController c;
  final VoidCallback onExport,
      onSeparate,
      onSettings,
      onGuide,
      onAbout,
      onResetView,
      onFrameSelected;
  final void Function(String) onView;
  final void Function(bool) onCurves;
  const StudioMenuBar({
    super.key,
    required this.c,
    required this.onExport,
    required this.onSeparate,
    required this.onSettings,
    required this.onGuide,
    required this.onAbout,
    required this.onResetView,
    required this.onFrameSelected,
    required this.onView,
    required this.onCurves,
  });
  Widget item(String label, VoidCallback? action, {String shortcut = ''}) =>
      MenuItemButton(
        onPressed: action,
        trailingIcon: shortcut.isEmpty
            ? null
            : Text(
                shortcut,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
  @override
  Widget build(BuildContext context) {
    final enabled = !c.busy && !c.moving,
        hasObject = enabled && c.selected != null;
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MenuBar(
          style: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(ink),
            elevation: WidgetStatePropertyAll(0),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
          ),
          children: [
            SubmenuButton(
              menuChildren: [
                item('新建工程', enabled ? c.newProject : null, shortcut: 'Ctrl+N'),
                item(
                  '打开工程…',
                  enabled ? c.openProject : null,
                  shortcut: 'Ctrl+O',
                ),
                item(
                  '保存单文件工程',
                  enabled ? c.saveProject : null,
                  shortcut: 'Ctrl+S',
                ),
                item(
                  '工程另存为…',
                  enabled ? () => c.saveProject(saveAs: true) : null,
                  shortcut: 'Ctrl+Shift+S',
                ),
                const Divider(),
                item(
                  '导入音频 / 视频音轨…',
                  enabled ? () => c.importAudio() : null,
                  shortcut: 'Ctrl+I',
                ),
                item('AI 部件拆分…', enabled ? onSeparate : null),
                item(
                  '导出混音…',
                  enabled && c.project.objects.isNotEmpty ? onExport : null,
                ),
                const Divider(),
                item('引擎与工作区…', enabled ? onSettings : null),
              ],
              child: const Text('文件'),
            ),
            SubmenuButton(
              menuChildren: [
                item(
                  '撤销',
                  enabled && c.undoStack.isNotEmpty ? c.undo : null,
                  shortcut: 'Ctrl+Z',
                ),
                item(
                  '重做',
                  enabled && c.redoStack.isNotEmpty ? c.redo : null,
                  shortcut: 'Ctrl+Shift+Z',
                ),
                const Divider(),
                item('复制对象', hasObject ? c.copySelected : null, shortcut: 'C'),
                item(
                  '粘贴到上次声场指针位置',
                  enabled && c.copiedObject != null && c.pointerWorld != null
                      ? () => c.pasteAt(c.pointerWorld!)
                      : null,
                  shortcut: 'V',
                ),
                item(
                  '独立复制并移动',
                  hasObject ? () => c.duplicate(move: true) : null,
                  shortcut: 'Shift+D',
                ),
                item(
                  '关联复制（共享声音参数）',
                  hasObject ? () => c.duplicate(linked: true) : null,
                  shortcut: 'Ctrl+D',
                ),
                item(
                  '解除参数关联',
                  hasObject && c.selected!.linkId.isNotEmpty
                      ? c.unlinkSelected
                      : null,
                ),
                const Divider(),
                item('移动对象', hasObject ? c.beginMove : null, shortcut: 'G'),
                item(
                  '从场景删除对象',
                  hasObject ? c.deleteObject : null,
                  shortcut: 'X / Delete',
                ),
              ],
              child: const Text('编辑'),
            ),
            SubmenuButton(
              menuChildren: [
                item('透视声场', () => onView('perspective')),
                item('正视声场', () => onView('front'), shortcut: 'Num 1'),
                item('俯视声场', () => onView('top'), shortcut: 'Num 7'),
                item('右视声场', () => onView('right'), shortcut: 'Num 3'),
                item('聚焦选中对象', onFrameSelected, shortcut: 'Num .'),
                item('重置视角', onResetView, shortcut: 'Home'),
                const Divider(),
                item('底部：关键帧', () => onCurves(false)),
                item('底部：动画曲线', () => onCurves(true)),
              ],
              child: const Text('视图'),
            ),
            SubmenuButton(
              menuChildren: [
                item('快速入门', onGuide, shortcut: 'F1'),
                item('快捷键与关于', onAbout),
              ],
              child: const Text('帮助'),
            ),
          ],
        ),
      ),
    );
  }
}
