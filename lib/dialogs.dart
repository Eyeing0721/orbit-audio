import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'studio_controller.dart';
import 'audio_formats.dart';

Future<void> rainSceneDialog(BuildContext context, StudioController c) async {
  final arrival = TextEditingController(text: '24');
  final rain = TextEditingController(text: '-7');
  final intensity = TextEditingController(text: '0.8');
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('雨夜沉浸声场'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '对当前未静音的音频对象应用可编辑的声场预设。\n识别人声、鼓、贝斯与旋律分轨，生成三层独立雨幕。\n人声从远到近，伴奏固定后侧，扩散与微移调制造包围感；不绕圈。',
              style: TextStyle(fontSize: 12, height: 1.8),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: arrival,
              decoration: const InputDecoration(labelText: '人声靠近所需秒数（1–120）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rain,
              decoration: const InputDecoration(
                labelText: '雨声输入增益（-36 到 0 dB，越大越明显）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: intensity,
              decoration: const InputDecoration(
                labelText: '混响 / 失真 / 调制强度（0–1）',
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '应用会替换这些对象的节点图、位置和动画，并解除其参数关联；原音频不会修改。可以整体撤销。已有本预设雨幕将更新，不重复堆叠。\n没有人声分轨时仍可使用，但雨幕不会跟随人声闪避。',
              style: TextStyle(fontSize: 11, height: 1.8),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('应用可编辑声场'),
        ),
      ],
    ),
  );
  if (yes == true) {
    double bounded(String text, double fallback, double min, double max) {
      final value = double.tryParse(text);
      return value != null && value.isFinite ? value.clamp(min, max) : fallback;
    }

    c.rainScene(
      arrival: bounded(arrival.text, 24, 1, 120),
      rainGain: bounded(rain.text, -7, -36, 0),
      intensity: bounded(intensity.text, .8, 0, 1),
    );
  }
  arrival.dispose();
  rain.dispose();
  intensity.dispose();
}

Future<void> exportDialog(BuildContext context, StudioController c) async {
  var format = 'wav24';
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('渲染空间音频'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '位置动画、混响、回声、失真与环境音，\n通过真实头相关函数渲染成双耳立体声。',
                style: TextStyle(fontSize: 13, height: 1.8),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: format,
                decoration: const InputDecoration(labelText: '输出格式'),
                isExpanded: true,
                items: audioExportFormats
                    .map(
                      (f) =>
                          DropdownMenuItem(value: f.id, child: Text(f.label)),
                    )
                    .toList(),
                onChanged: (v) => setLocal(() => format = v!),
              ),
              const SizedBox(height: 16),
              Text(
                '时长 ${c.project.duration.toStringAsFixed(2)} 秒 + ${c.project.tail.toStringAsFixed(1)} 秒尾音\n峰值保护 ${c.project.protectPeaks ? '开启（-1.2 dBFS）' : '关闭'} · 主增益 ${c.project.masterGain} dB',
                style: const TextStyle(fontSize: 12, height: 1.8),
              ),
              const SizedBox(height: 10),
              const Text(
                '普通耳机即可听到双耳空间效果。当前版本不提供 Dolby Atmos / ADM 编码。',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF979BA3),
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择保存位置'),
          ),
        ],
      ),
    ),
  );
  if (yes != true) return;
  final ext = audioExportFormats.firstWhere((f) => f.id == format).extension;
  final file = await getSaveLocation(
    suggestedName: '${c.project.name}_binaural.$ext',
    acceptedTypeGroups: [
      XTypeGroup(label: '音频', extensions: [ext]),
    ],
  );
  if (file == null) return;
  var path = file.path;
  if (!path.toLowerCase().endsWith('.$ext')) path += '.$ext';
  await c.renderTo(format, path);
  if (context.mounted && c.lastRender != null) {
    final report = c.lastRender!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('音频已导出'),
        content: SelectableText(
          '${report['path']}\n\n${report['duration']} 秒 · 48 kHz · 双耳立体声\n文件大小 ${((report['bytes'] as num) / 1048576).toStringAsFixed(2)} MiB\n编码前采样峰值 ${report['peakDb']} dBFS\n编码前 RMS ${report['rmsDb']} dBFS\n峰值保护衰减 ${report['attenuationDb']} dB\n\n不是 Dolby Atmos。RMS 不是 LUFS，采样峰值不是真峰值。',
          style: const TextStyle(fontSize: 12, height: 1.8),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}

Future<void> separationDialog(BuildContext context, StudioController c) async {
  String? source = c.selected?.generator.isEmpty == true
      ? c.selected?.path
      : null;
  String model = 'htdemucs_6s';
  final parts = <String>{'vocals', 'drums', 'bass', 'guitar', 'piano', 'other'};
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('AI 部件拆分'),
        scrollable: true,
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择想保留的部件，拆分后成为独立的声音对象。\n音频在本机处理；首次使用模型需要联网下载权重。',
                style: TextStyle(fontSize: 12, height: 1.8),
              ),
              const SizedBox(height: 15),
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await openFile(
                    acceptedTypeGroups: [
                      const XTypeGroup(
                        label: '音频',
                        extensions: audioImportExtensions,
                      ),
                    ],
                  );
                  if (f != null) setLocal(() => source = f.path);
                },
                icon: const Icon(Icons.audio_file_outlined),
                label: Text(
                  source?.split(RegExp(r'[/\\]')).last ?? '选择要拆分的音频',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                initialValue: model,
                decoration: const InputDecoration(labelText: '本地免费模型'),
                items: const [
                  DropdownMenuItem(
                    value: 'htdemucs_6s',
                    child: Text('Demucs 6s · 6 部件'),
                  ),
                  DropdownMenuItem(
                    value: 'htdemucs_ft',
                    child: Text('Demucs FT · 高质量 4 部件'),
                  ),
                  DropdownMenuItem(
                    value: 'htdemucs',
                    child: Text('Demucs · 标准 4 部件'),
                  ),
                ],
                onChanged: (v) => setLocal(() {
                  model = v!;
                  if (model != 'htdemucs_6s') {
                    parts.remove('guitar');
                    parts.remove('piano');
                  }
                }),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children:
                    {
                          'vocals': '人声',
                          'drums': '鼓组',
                          'bass': '贝斯',
                          'guitar': '吉他',
                          'piano': '钢琴',
                          'other': '其他',
                          'instrumental': '合成伴奏',
                        }.entries
                        .where(
                          (e) =>
                              model == 'htdemucs_6s' ||
                              !['guitar', 'piano'].contains(e.key),
                        )
                        .map(
                          (e) => FilterChip(
                            label: Text(e.value),
                            selected: parts.contains(e.key),
                            onSelected: (v) => setLocal(
                              () => v ? parts.add(e.key) : parts.remove(e.key),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 14),
              const Text(
                '模型会计算所有部件，再导入你选中的部分。原始对象保留并静音，避免重复叠加。',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF979BA3),
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: source != null && parts.isNotEmpty
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('开始拆分'),
          ),
        ],
      ),
    ),
  );
  if (yes == true && source != null) await c.separate(source!, model, parts);
}

Future<void> settingsDialog(BuildContext context, StudioController c) async {
  final python = TextEditingController(text: c.engine.python);
  final ffmpeg = TextEditingController(text: c.engine.ffmpeg);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('引擎与工作区'),
      scrollable: true,
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: python,
              decoration: const InputDecoration(
                labelText: 'Python 可执行文件（含音频依赖）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ffmpeg,
              decoration: const InputDecoration(
                labelText: 'FFmpeg 路径（留空使用系统 PATH）',
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              '引擎：${c.engine.root}\n工作区：${c.workspace}\nHRTF：${c.project.hrtf.isEmpty ? '内置 MIT KEMAR（真实测量数据）' : c.project.hrtf}\n渲染：48 kHz · 双耳卷积 · 本地处理',
              style: const TextStyle(fontSize: 11, height: 1.9),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await openFile(
                  acceptedTypeGroups: [
                    const XTypeGroup(label: 'SOFA HRTF', extensions: ['sofa']),
                  ],
                );
                if (f != null) {
                  c.remember();
                  c.project.hrtf = f.path;
                  c.changed();
                }
              },
              icon: const Icon(Icons.hearing_outlined, size: 16),
              label: const Text('载入自定义 SOFA'),
            ),
            TextButton(
              onPressed: () {
                c.remember();
                c.project.hrtf = '';
                c.changed();
              },
              child: const Text('恢复内置 KEMAR'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () async {
            await c.saveSettings(python.text, ffmpeg.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('保存设置'),
        ),
      ],
    ),
  );
  python.dispose();
  ffmpeg.dispose();
}

Future<void> renameDialog(BuildContext context, StudioController c) async {
  if (c.selected == null) return;
  final controller = TextEditingController(text: c.selected!.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('重命名对象'),
      scrollable: true,
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (name != null) c.rename(name);
  controller.dispose();
}

Future<void> projectDialog(BuildContext context, StudioController c) async {
  final name = TextEditingController(text: c.project.name);
  final duration = TextEditingController(
    text: c.project.duration.toStringAsFixed(2),
  );
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('工程设置'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '工程名称'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: duration,
              decoration: const InputDecoration(labelText: '工程时长 / 秒'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (yes == true) {
    c.remember();
    if (name.text.trim().isNotEmpty) c.project.name = name.text.trim();
    final sec = double.tryParse(duration.text);
    if (sec != null) c.project.duration = sec.clamp(1, 36000);
    c.changed();
  }
  name.dispose();
  duration.dispose();
}
