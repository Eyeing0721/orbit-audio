import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'audio_formats.dart';
import 'models.dart';
import 'studio_controller.dart';
import 'studio_slider.dart';
import 'studio_style.dart';

class ClipEditor extends StatefulWidget {
  final StudioController controller;
  const ClipEditor({super.key, required this.controller});
  @override
  State<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<ClipEditor> {
  StudioController get c => widget.controller;
  double anchor = 0;
  @override
  Widget build(BuildContext context) {
    final object = c.selected;
    if (object == null) {
      return const Center(
        child: Text(
          '选择音频对象后开始非破坏性编辑',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      );
    }
    final start = (object.clip['trimStart'] as num? ?? 0).toDouble();
    final end = (object.clip['trimEnd'] as num? ?? 0).toDouble();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          object.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'NON-DESTRUCTIVE / 源 ${object.duration.toStringAsFixed(2)}s → 片段 ${object.clipDuration.toStringAsFixed(2)}s',
          style: const TextStyle(
            fontFamily: 'Bahnschrift',
            fontSize: 10,
            letterSpacing: .7,
            color: accent,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, bounds) {
              double at(double dx) => (dx / bounds.maxWidth * object.duration)
                  .clamp(0, math.max(0, object.duration - .001));
              return GestureDetector(
                key: const ValueKey('clip-waveform'),
                behavior: HitTestBehavior.opaque,
                onPanDown: c.busy
                    ? null
                    : (event) => anchor = at(event.localPosition.dx),
                onPanStart: c.busy
                    ? null
                    : (event) {
                        c.remember();
                        final position = at(event.localPosition.dx);
                        c.updateClip({
                          'trimStart': math.min(anchor, position),
                          'trimEnd': math.min(
                            object.duration,
                            math.max(anchor, position) + .001,
                          ),
                        }, record: false);
                      },
                onPanUpdate: c.busy
                    ? null
                    : (event) {
                        final position = at(event.localPosition.dx);
                        c.updateClip({
                          'trimStart': math.min(anchor, position),
                          'trimEnd': math.min(
                            object.duration,
                            math.max(anchor, position) + .001,
                          ),
                        }, record: false);
                      },
                child: CustomPaint(
                  painter: _ClipWaveform(
                    object,
                    start,
                    end == 0 ? object.duration : end,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '源波形 · 拖动选择裁剪区间；原始文件保持不变',
          style: TextStyle(fontSize: 10, color: muted),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 15,
          runSpacing: 18,
          children: [
            numeric(
              'trimStart',
              '裁剪起点 / s',
              start,
              0,
              math.max(0, (end == 0 ? object.duration : end) - .001),
            ),
            numeric('trimEnd', '裁剪终点 / s（0=结尾）', end, 0, object.duration),
            numeric(
              'fadeIn',
              '淡入 / s',
              (object.clip['fadeIn'] as num? ?? 0).toDouble(),
              0,
              30,
            ),
            numeric(
              'fadeOut',
              '淡出 / s',
              (object.clip['fadeOut'] as num? ?? 0).toDouble(),
              0,
              30,
            ),
            numeric(
              'speed',
              '播放速度 / 同时变调',
              (object.clip['speed'] as num? ?? 1).toDouble(),
              .25,
              4,
            ),
            numeric(
              'targetPeak',
              '归一化目标 / dBFS',
              (object.clip['targetPeak'] as num? ?? -1).toDouble(),
              -24,
              0,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final option in {
              'reverse': '反转片段',
              'invert': '反相',
              'normalize': '采样峰值归一化',
            }.entries)
              FilterChip(
                key: ValueKey('clip-${option.key}'),
                label: Text(option.value, style: const TextStyle(fontSize: 11)),
                selected: object.clip[option.key] == true,
                onSelected: c.busy
                    ? null
                    : (value) => c.updateClip({option.key: value}),
              ),
            ActionChip(
              label: const Text('重置源级处理', style: TextStyle(fontSize: 11)),
              onPressed: c.busy ? null : () => c.updateClip({}, reset: true),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          '处理顺序：裁剪 → 反转 → 变速 → 归一化 / 反相 → 淡入淡出。\n片段以对象“偏移”放入工程；缩短片段不会自动缩短整个工程。当前变速会同时改变音高，并非保调时间拉伸。关联副本共享这些源级设置。',
          style: TextStyle(fontSize: 11, color: muted, height: 1.8),
        ),
      ],
    );
  }

  Widget numeric(
    String field,
    String label,
    double value,
    double min,
    double max,
  ) => SizedBox(
    width: 190,
    child: TextFormField(
      key: ValueKey('clip-$field-${c.selectedId}-$value'),
      initialValue: value.toStringAsFixed(3),
      enabled: !c.busy,
      style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 10),
      ),
      onFieldSubmitted: (text) {
        final parsed = double.tryParse(text);
        if (parsed == null || !parsed.isFinite) return;
        var result = parsed.clamp(min, max);
        if (field == 'trimEnd' && result != 0) {
          result = math
              .max(result, (c.selected!.clip['trimStart'] as num? ?? 0) + .001)
              .clamp(0, c.selected!.duration);
        }
        c.updateClip({field: result});
      },
    ),
  );
}

class _ClipWaveform extends CustomPainter {
  final SoundObject object;
  final double start, end;
  _ClipWaveform(this.object, this.start, this.end);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF191C21),
    );
    final center = size.height / 2;
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()..color = line,
    );
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(
        Offset(size.width * i / 10, 0),
        Offset(size.width * i / 10, size.height),
        Paint()..color = line.withValues(alpha: .3),
      );
    }
    final selection = Rect.fromLTRB(
      start / object.duration * size.width,
      0,
      end / object.duration * size.width,
      size.height,
    );
    canvas.drawRect(selection, Paint()..color = accent.withValues(alpha: .12));
    final paint = Paint()
      ..color = object.color.withValues(alpha: .9)
      ..strokeWidth = 1;
    final peaks = object.waveform;
    for (var i = 0; i < peaks.length; i++) {
      final x = i / peaks.length * size.width,
          amplitude = math.min(1.0, peaks[i]) * (size.height * .4);
      canvas.drawLine(
        Offset(x, center - amplitude),
        Offset(x, center + amplitude),
        paint,
      );
    }
    for (final x in [selection.left, selection.right]) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = accent
          ..strokeWidth = 2,
      );
    }
    if (peaks.isEmpty) {
      final text = TextPainter(
        text: const TextSpan(
          text: '无缓存源波形 · 可在频谱工作区分析实际音频',
          style: TextStyle(color: muted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 20);
      text.paint(canvas, const Offset(10, 12));
    }
  }

  @override
  bool shouldRepaint(covariant _ClipWaveform oldDelegate) => true;
}

class SpectrumEditor extends StatefulWidget {
  final StudioController controller;
  const SpectrumEditor({super.key, required this.controller});
  @override
  State<SpectrumEditor> createState() => SpectrumEditorState();
}

class SpectrumEditorState extends State<SpectrumEditor> {
  StudioController get c => widget.controller;
  Map<String, dynamic>? decoded;
  ui.Image? image;
  Future<void>? imageReady;
  bool linePlot = false, processed = true;
  double start = 0, seconds = 12;
  String channel = 'mono';
  int generation = 0;
  @override
  void initState() {
    super.initState();
    c.addListener(syncAnalysis);
    syncAnalysis();
  }

  @override
  void didUpdateWidget(covariant SpectrumEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(syncAnalysis);
      c.addListener(syncAnalysis);
      syncAnalysis();
    }
  }

  void syncAnalysis() {
    final data = c.analysisObjectId == c.selectedId ? c.analysis : null;
    if (identical(decoded, data)) return;
    decoded = data;
    if (data == null) {
      generation++;
      image?.dispose();
      image = null;
    } else {
      decode(data);
    }
  }

  @override
  void dispose() {
    c.removeListener(syncAnalysis);
    generation++;
    image?.dispose();
    super.dispose();
  }

  void decode(Map<String, dynamic> data) {
    final completion = Completer<void>();
    imageReady = completion.future;
    final id = ++generation;
    final width = data['width'] as int, height = data['height'] as int;
    final values = base64Decode(data['pixels'] as String),
        rgba = Uint8List(width * height * 4);
    const colors = [
      Color(0xFF111820),
      Color(0xFF203D59),
      Color(0xFF3D8193),
      Color(0xFF7FC0A6),
      Color(0xFFE5BD79),
      Color(0xFFF5E7B8),
    ];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final level =
            values[(height - 1 - y) * width + x] / 255 * (colors.length - 1);
        final color = Color.lerp(
          colors[level.floor()],
          colors[math.min(colors.length - 1, level.floor() + 1)],
          level % 1,
        )!;
        final at = (y * width + x) * 4;
        rgba[at] = (color.r * 255).round();
        rgba[at + 1] = (color.g * 255).round();
        rgba[at + 2] = (color.b * 255).round();
        rgba[at + 3] = 255;
      }
    }
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, (
      result,
    ) {
      if (!mounted || generation != id) {
        result.dispose();
        completion.complete();
        return;
      }
      setState(() {
        image?.dispose();
        image = result;
      });
      completion.complete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = c.analysisObjectId == c.selectedId ? c.analysis : null;
    return Column(
      children: [
        Container(
          height: 43,
          color: const Color(0xFF25272C),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const ValueKey('analyze-audio'),
                  onPressed: c.busy || c.selected == null
                      ? null
                      : () => c.analyzeSelected(
                          start: start,
                          seconds: seconds,
                          processed: processed,
                          channel: channel,
                        ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.analytics_outlined, size: 15),
                  label: const Text('分析选中音频', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(
                    processed ? '剪辑/节点后' : '原始源',
                    style: const TextStyle(fontSize: 10),
                  ),
                  selected: processed,
                  onSelected: (value) => setState(() => processed = value),
                  showCheckmark: false,
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: channel,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: white,
                    fontFamily: 'Segoe UI',
                    fontFamilyFallback: [
                      'Microsoft YaHei UI',
                      'Microsoft YaHei',
                    ],
                  ),
                  items: const [
                    DropdownMenuItem(value: 'mono', child: Text('单声道平均')),
                    DropdownMenuItem(value: 'left', child: Text('左声道')),
                    DropdownMenuItem(value: 'right', child: Text('右声道')),
                  ],
                  onChanged: (value) => setState(() => channel = value!),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  height: 32,
                  child: TextFormField(
                    initialValue: '0',
                    style: const TextStyle(fontSize: 10),
                    decoration: const InputDecoration(
                      prefixText: '起点 ',
                      suffixText: 's',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                    ),
                    onChanged: (value) {
                      final number = double.tryParse(value);
                      if (number != null && number.isFinite && number >= 0) {
                        start = number;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<double>(
                  value: seconds,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: white,
                    fontFamily: 'Segoe UI',
                    fontFamilyFallback: [
                      'Microsoft YaHei UI',
                      'Microsoft YaHei',
                    ],
                  ),
                  items: [1.0, 5.0, 12.0, 30.0]
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text('${s.toInt()}s'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => seconds = value!),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        Container(
          height: 33,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => linePlot = false),
                child: Text(
                  '声谱图',
                  style: TextStyle(
                    fontSize: 10,
                    color: !linePlot ? accent : muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => linePlot = true),
                child: Text(
                  '频率曲线',
                  style: TextStyle(
                    fontSize: 10,
                    color: linePlot ? accent : muted,
                  ),
                ),
              ),
              const Spacer(),
              if (data != null)
                Expanded(
                  flex: 3,
                  child: Text(
                    c.analysisStale
                        ? '参数已改 · 需重新分析'
                        : 'PEAK ${data['peakDb']} / RMS ${data['rmsDb']} dBFS',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 9,
                      color: c.analysisStale ? const Color(0xFFE2B47C) : muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: data == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '分析实际音频后显示 STFT 声谱与频率曲线\n40 Hz – 20 kHz · 对数频率 · −100 至 0 dBFS\n不会自动下载素材或生成示意数据',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12, height: 2),
                    ),
                  ),
                )
              : GestureDetector(
                  onTapDown: !linePlot && data['processed'] == true
                      ? (event) {
                          final box = context.findRenderObject() as RenderBox?;
                          if (box != null) {
                            c.seek(
                              (c.selected!.offset +
                                      (data['start'] as num).toDouble() +
                                      ((event.localPosition.dx - 48) /
                                                  math.max(
                                                    1,
                                                    box.size.width - 64,
                                                  ))
                                              .clamp(0, 1) *
                                          (data['seconds'] as num))
                                  .clamp(0, c.project.duration),
                            );
                          }
                        }
                      : null,
                  child: CustomPaint(
                    key: const ValueKey('spectral-plot'),
                    size: Size.infinite,
                    painter: _SpectralPainter(data, image, linePlot),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 8),
          child: Text(
            data == null
                ? '选中单个对象 · 手动分析 · 不是实时总线分析仪'
                : '${data['processed'] == true ? '剪辑/节点后' : '原始源'} · ${data['channel']} · ${(data['seconds'] as num).toStringAsFixed(2)}s · 源级分析，不含对象音效/空间与主总线',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: muted),
          ),
        ),
      ],
    );
  }
}

class _SpectralPainter extends CustomPainter {
  final Map<String, dynamic> data;
  final ui.Image? image;
  final bool linePlot;
  _SpectralPainter(this.data, this.image, this.linePlot);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF131820),
    );
    final plot = Rect.fromLTRB(
      48,
      12,
      math.max(49, size.width - 16),
      math.max(13, size.height - 26),
    );
    void text(String label, Offset at) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Consolas',
            color: muted,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at);
    }

    final grid = Paint()
      ..color = line.withValues(alpha: .55)
      ..strokeWidth = .5;
    double frequency(double hz) => math.log(hz / 40) / math.log(20000 / 40);
    if (!linePlot && image != null) {
      canvas.drawImageRect(
        image!,
        Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
        plot,
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    if (linePlot) {
      for (final hz in [100.0, 1000.0, 10000.0]) {
        final x = plot.left + frequency(hz) * plot.width;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
        text(
          hz >= 1000 ? '${(hz / 1000).toInt()}k Hz' : '${hz.toInt()} Hz',
          Offset(x - 15, plot.bottom + 8),
        );
      }
      for (final db in [-100, -80, -60, -40, -20, 0]) {
        final y = plot.bottom - (db + 100) / 100 * plot.height;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        text('$db', Offset(9, y - 5));
      }
      final values = (data['spectrumDb'] as List).cast<num>(),
          frequencies = (data['frequencies'] as List).cast<num>();
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = plot.left + frequency(frequencies[i].toDouble()) * plot.width,
            y =
                plot.bottom -
                ((values[i].toDouble() + 100) / 100).clamp(0, 1) * plot.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..strokeWidth = 1.7
          ..style = PaintingStyle.stroke,
      );
    } else {
      for (final hz in [100.0, 1000.0, 10000.0]) {
        final y = plot.bottom - frequency(hz) * plot.height;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        text(
          hz >= 1000 ? '${(hz / 1000).toInt()}k' : '${hz.toInt()}',
          Offset(9, y - 5),
        );
      }
      for (var i = 0; i <= 4; i++) {
        final x = plot.left + plot.width * i / 4;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
        text(
          '${((data['start'] as num) + (data['seconds'] as num) * i / 4).toStringAsFixed(1)}s',
          Offset(x - 10, plot.bottom + 8),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpectralPainter oldDelegate) => true;
}

class MixerPanel extends StatelessWidget {
  final StudioController controller;
  const MixerPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      children: [
        const SizedBox(
          height: 34,
          child: Center(
            child: Text(
              'OBJECT GAIN / 预渲染监听；此处不是实时电平表',
              style: TextStyle(
                fontFamily: 'Bahnschrift',
                fontSize: 10,
                color: muted,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final object in c.project.objects) strip(c, object),
                strip(c, null),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget strip(StudioController c, SoundObject? object) => SizedBox(
    width: 130,
    child: Container(
      margin: const EdgeInsets.fromLTRB(5, 0, 5, 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2D33),
        border: Border(
          top: BorderSide(color: object?.color ?? accent, width: 3),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, bounds) => Column(
          children: [
            InkWell(
              onTap: object == null ? null : () => c.select(object.id),
              child: Text(
                object?.name ?? 'MASTER',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 9),
            if (object != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final mute in [true, false])
                    InkWell(
                      onTap: c.busy
                          ? null
                          : () {
                              c.select(object.id);
                              c.remember();
                              if (mute) {
                                object.mute = !object.mute;
                              } else {
                                object.solo = !object.solo;
                              }
                              c.changed();
                            },
                      child: Container(
                        width: 35,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        alignment: Alignment.center,
                        color: (mute ? object.mute : object.solo)
                            ? const Color(0xFF495A77)
                            : ink,
                        child: Text(
                          mute ? 'M' : 'S',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                ],
              )
            else
              const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: math.max(30, bounds.maxHeight - 110),
                    height: 32,
                    child: StudioSlider(
                      value:
                          (object?.value('gain', c.cursor) ??
                                  c.project.masterGain)
                              .clamp(-48, 12),
                      min: -48,
                      max: 12,
                      onChangeStart: c.busy
                          ? null
                          : (_) {
                              if (object != null) c.select(object.id);
                              c.remember();
                            },
                      onChanged: c.busy
                          ? null
                          : (value) {
                              if (object == null) {
                                c.project.masterGain = value;
                                c.changed();
                              } else {
                                c.updateValue('gain', value);
                              }
                            },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              '${(object?.value('gain', c.cursor) ?? c.project.masterGain).toStringAsFixed(1)} dB',
              style: const TextStyle(
                fontFamily: 'Consolas',
                color: accent,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              object == null
                  ? '48 kHz / STEREO'
                  : (object.linkId.isNotEmpty ? 'LINKED DATA' : 'OBJECT'),
              style: const TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class WorkflowPage extends StatelessWidget {
  final String type;
  final StudioController controller;
  final VoidCallback onSeparate, onExport;
  const WorkflowPage({
    super.key,
    required this.type,
    required this.controller,
    required this.onSeparate,
    required this.onExport,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller, exporting = type == 'export';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          exporting ? '渲染与交付' : '素材与部件拆分',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 9),
        Text(
          exporting ? '同一工程 · 对象与节点一起参与空间渲染' : '原始素材 → 可选择部件 → 独立声音对象',
          style: const TextStyle(color: accent, fontSize: 11),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: c.busy || exporting && c.project.objects.isEmpty
                  ? null
                  : exporting
                  ? onExport
                  : () => c.importAudio(),
              icon: Icon(
                exporting ? Icons.file_upload_outlined : Icons.add,
                size: 17,
              ),
              label: Text(
                exporting ? '选择格式并渲染' : '导入本地音频',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            OutlinedButton.icon(
              onPressed: c.busy
                  ? null
                  : exporting
                  ? c.saveProject
                  : onSeparate,
              icon: Icon(
                exporting ? Icons.save_outlined : Icons.call_split,
                size: 17,
              ),
              label: Text(
                exporting ? '保存完整工程' : '选择模型与拆分部件',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        if (exporting) ...[
          const Text(
            'OUTPUT PRESETS',
            style: TextStyle(fontSize: 10, color: muted, letterSpacing: 1.3),
          ),
          const SizedBox(height: 12),
          for (final format in audioExportFormats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(format.label, style: const TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 20),
          const Text(
            '输出为耳机双耳立体声，不是 Dolby Atmos ADM/JOC。\n48 kHz；峰值保护为采样峰值保护，不是 LUFS 归一化。\n未启用的节点图会旁路；未连接的节点输出会静音。',
            style: TextStyle(fontSize: 11, color: muted, height: 1.9),
          ),
        ] else ...[
          const Text(
            'MEDIA INVENTORY',
            style: TextStyle(fontSize: 10, color: muted, letterSpacing: 1.3),
          ),
          const SizedBox(height: 14),
          if (c.project.objects.isEmpty)
            const Text(
              '尚无素材。可以导入音频，或从左侧添加环境音。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          for (final object in c.project.objects)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => c.select(object.id),
              leading: Icon(
                object.generator.isEmpty
                    ? Icons.audio_file_outlined
                    : Icons.water_drop_outlined,
                color: object.color,
                size: 20,
              ),
              title: Text(object.name, style: const TextStyle(fontSize: 12)),
              subtitle: Text(
                '${object.duration.toStringAsFixed(2)}s · ${object.generator.isEmpty ? object.path : '本地生成 ${object.generator}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Demucs 6s：人声 / 鼓组 / 贝斯 / 吉他 / 钢琴 / 其他。\n选定部件会作为独立对象导入；原始对象保留并静音。\n首次使用模型可能下载权重，音频仍在本机处理。',
            style: TextStyle(fontSize: 11, color: muted, height: 1.9),
          ),
        ],
      ],
    );
  }
}
