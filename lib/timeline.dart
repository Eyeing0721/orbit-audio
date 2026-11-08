import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

class AudioTimeline extends StatefulWidget {
  final AudioProject project;
  final double cursor;
  final String? selected;
  final void Function(double) onSeek;
  final void Function(String) onSelect;
  final void Function(String, int, double) onRetime;
  final VoidCallback onBeginEdit;
  const AudioTimeline({
    super.key,
    required this.project,
    required this.cursor,
    required this.selected,
    required this.onSeek,
    required this.onSelect,
    required this.onRetime,
    required this.onBeginEdit,
  });
  @override
  State<AudioTimeline> createState() => _AudioTimelineState();
}

class _AudioTimelineState extends State<AudioTimeline> {
  AudioProject get project => widget.project;
  double get cursor => widget.cursor;
  String? get selected => widget.selected;
  void Function(double) get onSeek => widget.onSeek;
  void Function(String) get onSelect => widget.onSelect;
  void Function(String, int, double) get onRetime => widget.onRetime;
  VoidCallback get onBeginEdit => widget.onBeginEdit;
  int? draggingKey;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      const labelWidth = 224.0;
      final width = math.max(100.0, bounds.maxWidth - labelWidth - 20);
      double timeAt(double dx) =>
          (dx / width * project.duration).clamp(0, project.duration);
      return Column(
        children: [
          SizedBox(
            height: 30,
            child: Row(
              children: [
                const SizedBox(
                  width: labelWidth,
                  child: Padding(
                    padding: EdgeInsets.only(left: 18),
                    child: Text(
                      '对象 / 自动化',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF959CA7),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTapDown: (e) => onSeek(timeAt(e.localPosition.dx)),
                    onPanUpdate: (e) => onSeek(timeAt(e.localPosition.dx)),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: RulerPainter(project.duration, cursor),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: project.objects.isEmpty
                ? const Center(
                    child: Text(
                      '导入音频后，波形与关键帧会显示在这里',
                      style: TextStyle(color: Color(0xFF7A8390), fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: project.objects.length,
                    itemExtent: 47,
                    itemBuilder: (context, index) {
                      final obj = project.objects[index];
                      return Row(
                        children: [
                          SizedBox(
                            width: labelWidth,
                            child: InkWell(
                              onTap: () => onSelect(obj.id),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: selected == obj.id
                                      ? const Color(0xFF343A43)
                                      : const Color(0xFF27292D),
                                  border: const Border(
                                    bottom: BorderSide(
                                      color: Color(0xFF36383E),
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 24,
                                      color: obj.color,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        obj.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: selected == obj.id
                                              ? const Color(0xFFD2D8E2)
                                              : const Color(0xFFA1A8B4),
                                        ),
                                      ),
                                    ),
                                    if (obj.keyframes.isNotEmpty)
                                      Text(
                                        '${obj.keyframes.length} ◆',
                                        style: TextStyle(
                                          color: obj.color.withValues(
                                            alpha: .6,
                                          ),
                                          fontSize: 9,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, b) {
                                return GestureDetector(
                                  onTapDown: (e) {
                                    onSelect(obj.id);
                                    onSeek(timeAt(e.localPosition.dx));
                                  },
                                  onPanDown: (e) {
                                    draggingKey = null;
                                    for (
                                      var k = 0;
                                      k < obj.keyframes.length;
                                      k++
                                    ) {
                                      if ((obj.keyframes[k]['time']! /
                                                      project.duration *
                                                      width -
                                                  e.localPosition.dx)
                                              .abs() <
                                          10) {
                                        draggingKey = k;
                                        break;
                                      }
                                    }
                                  },
                                  onPanStart: (e) {
                                    if (draggingKey != null) {
                                      onBeginEdit();
                                      onRetime(
                                        obj.id,
                                        draggingKey!,
                                        timeAt(e.localPosition.dx),
                                      );
                                    }
                                  },
                                  onPanUpdate: (e) {
                                    if (draggingKey != null) {
                                      onRetime(
                                        obj.id,
                                        draggingKey!,
                                        timeAt(e.localPosition.dx),
                                      );
                                    } else {
                                      onSeek(timeAt(e.localPosition.dx));
                                    }
                                  },
                                  onPanEnd: (_) => draggingKey = null,
                                  child: CustomPaint(
                                    size: Size.infinite,
                                    painter: TrackPainter(
                                      obj,
                                      project.duration,
                                      cursor,
                                      selected == obj.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class RulerPainter extends CustomPainter {
  final double duration, cursor;
  RulerPainter(this.duration, this.cursor);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF292B30));
    final step = duration > 180
        ? 30
        : duration > 60
        ? 10
        : 5;
    for (var t = 0; t <= duration; t += step) {
      final x = t / duration * (s.width - 20);
      c.drawLine(
        Offset(x, s.height - 6),
        Offset(x, s.height),
        Paint()..color = const Color(0xFF777F8B),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 9,
            color: Color(0xFF969EAB),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(x + 5, 6));
    }
    final x = cursor / duration * (s.width - 20);
    final triangle = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x + 5, 18)
      ..lineTo(x, 24)
      ..lineTo(x - 5, 18)
      ..close();
    c.drawPath(triangle, Paint()..color = const Color(0xFF90B7DD));
  }

  @override
  bool shouldRepaint(covariant RulerPainter old) => true;
}

class TrackPainter extends CustomPainter {
  final SoundObject obj;
  final double duration, cursor;
  final bool selected;
  TrackPainter(this.obj, this.duration, this.cursor, this.selected);
  @override
  void paint(Canvas c, Size s) {
    final width = s.width - 20, height = s.height;
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..color = selected ? const Color(0xFF303741) : const Color(0xFF23252A),
    );
    c.drawLine(
      Offset(0, height),
      Offset(s.width, height),
      Paint()
        ..color = const Color(0xFF3A3D44)
        ..strokeWidth = .6,
    );
    final left = obj.offset / duration * width,
        clipWidth =
            math.min(obj.duration, duration - obj.offset) / duration * width;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + 1, 6, math.max(1, clipWidth - 2), height - 12),
      const Radius.circular(3),
    );
    c.drawRRect(
      rect,
      Paint()..color = obj.color.withValues(alpha: obj.mute ? 0.025 : .08),
    );
    c.save();
    c.clipRRect(rect);
    final path = Path();
    final visualPeak = obj.waveform.fold(.001, (a, b) => math.max(a, b));
    for (var x = 0.0; x < clipWidth; x += 2.2) {
      final index = (x / clipWidth * obj.waveform.length).floor();
      final amplitude = obj.waveform.isNotEmpty
          ? obj.waveform[index.clamp(0, obj.waveform.length - 1)]
          : obj.generator.isNotEmpty
          ? 0.18 + .10 * math.sin(x * .71).abs()
          : 0.0;
      final displayAmplitude = obj.waveform.isEmpty
          ? amplitude
          : math.pow((amplitude / visualPeak).clamp(0, 1), .6).toDouble();
      final a = math.min(1.0, displayAmplitude) * height * .38;
      path.moveTo(left + x, height / 2 - a);
      path.lineTo(left + x, height / 2 + a);
    }
    c.drawPath(
      path,
      Paint()
        ..color = obj.color.withValues(alpha: obj.mute ? 0.15 : .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    c.restore();
    for (final key in obj.keyframes) {
      final x = key['time']! / duration * width;
      final path = Path()
        ..moveTo(x, height / 2 - 5)
        ..lineTo(x + 5, height / 2)
        ..lineTo(x, height / 2 + 5)
        ..lineTo(x - 5, height / 2)
        ..close();
      c.drawPath(path, Paint()..color = obj.color);
      c.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF22252B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final playX = cursor / duration * width;
    c.drawLine(
      Offset(playX, 0),
      Offset(playX, height),
      Paint()
        ..color = const Color(0xFF90B7DD)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant TrackPainter old) => true;
}
