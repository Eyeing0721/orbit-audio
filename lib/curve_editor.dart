import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'studio_controller.dart';
import 'studio_style.dart';

const curveChannels = <String, (String, double, double, Color)>{
  'x': ('X · 左右', -1000000, 1000000, Color(0xFFE88881)),
  'y': ('Y · 前后', -1000000, 1000000, Color(0xFFA9C980)),
  'z': ('Z · 高度', -1000000, 1000000, Color(0xFF8AB8EC)),
  'gain': ('音量 · dB', -48, 12, Color(0xFFD5A477)),
  'spread': ('声像宽度', 0, 1, Color(0xFFAA9CC7)),
  'reverb': ('混响量', 0, 1, Color(0xFF72C4BD)),
  'echo': ('回声量', 0, .9, Color(0xFFC98D9E)),
  'distortion': ('失真量', 0, 1, Color(0xFFC8AF72)),
};

class CurvePointEdit {
  static Map<String, double> move(
    SoundObject object,
    String field,
    Map<String, double> key,
    double time,
    double value,
    double duration,
  ) {
    final neighbors =
        object.keyframes.where((k) => k != key && k.containsKey(field)).toList()
          ..sort((a, b) => a['time']!.compareTo(b['time']!));
    final oldTime = key['time']!, oldValue = key[field]!;
    final before = neighbors.where((k) => k['time']! < oldTime).lastOrNull;
    final after = neighbors.where((k) => k['time']! > oldTime).firstOrNull;
    time = time.clamp(
      before == null ? 0 : before['time']! + .001,
      after == null ? duration : after['time']! - .001,
    );
    final spec = curveChannels[field]!;
    value = value.clamp(spec.$2, spec.$3);
    final content = <String, double>{'time': time};
    for (final name
        in key.keys
            .where((k) => k == field || k.startsWith('$field.'))
            .toList()) {
      var v = key.remove(name)!;
      if (name == field || name.endsWith('V')) v += value - oldValue;
      if (name.endsWith('T')) v += time - oldTime;
      content[name] = v;
    }
    if (key.length == 1) object.keyframes.remove(key);
    final target =
        object.keyframes
            .where((k) => (k['time']! - time).abs() < .000001)
            .firstOrNull ??
        <String, double>{'time': time};
    if (!object.keyframes.contains(target)) object.keyframes.add(target);
    target.addAll(content);
    object.keyframes.sort((a, b) => a['time']!.compareTo(b['time']!));
    return target;
  }

  static void remove(
    SoundObject object,
    String field,
    Map<String, double> key,
  ) {
    key.removeWhere((name, _) => name == field || name.startsWith('$field.'));
    if (key.length == 1) object.keyframes.remove(key);
  }
}

class CurveEditor extends StatefulWidget {
  final StudioController controller;
  const CurveEditor({super.key, required this.controller});
  @override
  State<CurveEditor> createState() => CurveEditorState();
}

class CurveEditorState extends State<CurveEditor> {
  StudioController get c => widget.controller;
  String field = 'y';
  Map<String, double>? selected;
  String? dragPart;
  double minT = 0, maxT = 30, minV = -1, maxV = 8;
  String? framedObject;
  final focus = FocusNode();
  Rect plot = Rect.zero;
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  List<Map<String, double>> get points =>
      (c.selected?.keyframes.where((k) => k.containsKey(field)).toList() ?? [])
        ..sort((a, b) => a['time']!.compareTo(b['time']!));
  void fit() {
    final values = points
        .expand(
          (k) => [
            k[field]!,
            if (k.containsKey('$field.inV')) k['$field.inV']!,
            if (k.containsKey('$field.outV')) k['$field.outV']!,
          ],
        )
        .toList();
    if (values.isEmpty) values.add(c.selected?.values[field] ?? 0);
    minT = 0;
    maxT = points.isEmpty
        ? c.project.duration
        : math.min(
            c.project.duration,
            math.max(1, points.last['time']!) * 1.05,
          );
    final low = values.reduce(math.min),
        high = values.reduce(math.max),
        margin = math.max(
          (high - low) * .2,
          field == 'gain'
              ? 3.0
              : field == 'x' || field == 'y' || field == 'z'
              ? 1.0
              : .1,
        );
    minV = low - margin;
    maxV = high + margin;
  }

  Offset point(double time, double value) => Offset(
    plot.left + (time - minT) / (maxT - minT) * plot.width,
    plot.bottom - (value - minV) / (maxV - minV) * plot.height,
  );
  Offset data(Offset at) => Offset(
    minT + (at.dx - plot.left) / plot.width * (maxT - minT),
    minV + (plot.bottom - at.dy) / plot.height * (maxV - minV),
  );
  Offset? handle(Map<String, double> key, bool incoming) {
    final list = points, index = list.indexOf(key);
    if (index < 0 || (incoming ? index == 0 : index == list.length - 1)) {
      return null;
    }
    final neighbor = list[index + (incoming ? -1 : 1)]['time']!;
    final time =
        key['$field.${incoming ? 'in' : 'out'}T'] ??
        key['time']! + (neighbor - key['time']!) / 3;
    return Offset(
      time,
      key['$field.${incoming ? 'in' : 'out'}V'] ?? key[field]!,
    );
  }

  void pick(Offset at) {
    dragPart = null;
    if (c.selected?.modeFor(field) == 'bezier' && selected != null) {
      for (final incoming in [true, false]) {
        final h = handle(selected!, incoming);
        if (h != null && (point(h.dx, h.dy) - at).distance < 10) {
          dragPart = incoming ? 'in' : 'out';
          return;
        }
      }
    }
    for (final key in points) {
      if ((point(key['time']!, key[field]!) - at).distance < 10) {
        selected = key;
        dragPart = 'point';
        return;
      }
    }
  }

  void insert(double time, double value) {
    final object = c.selected;
    if (object == null || c.busy || c.moving) return;
    c.remember();
    time = time.clamp(0, c.project.duration);
    final key =
        object.keyframes
            .where((k) => (k['time']! - time).abs() < .001)
            .firstOrNull ??
        {'time': time};
    if (!object.keyframes.contains(key)) object.keyframes.add(key);
    final spec = curveChannels[field]!;
    key[field] = value.clamp(spec.$2, spec.$3);
    object.keyframes.sort((a, b) => a['time']!.compareTo(b['time']!));
    selected = key;
    c.changed();
    setState(() {});
  }

  void remove() {
    if (selected == null || c.selected == null || c.busy || c.moving) return;
    c.remember();
    CurvePointEdit.remove(c.selected!, field, selected!);
    selected = null;
    c.changed();
    setState(() {});
  }

  void dragTo(Offset at) {
    if (c.selected == null || selected == null || c.busy || c.moving) return;
    final value = data(at);
    if (dragPart == 'point') {
      selected = CurvePointEdit.move(
        c.selected!,
        field,
        selected!,
        value.dx,
        value.dy,
        c.project.duration,
      );
    } else if (dragPart != null) {
      final list = points, index = list.indexOf(selected!);
      final neighbor = list[index + (dragPart == 'in' ? -1 : 1)]['time']!;
      final spec = curveChannels[field]!;
      selected!['$field.${dragPart}T'] = value.dx.clamp(
        math.min(neighbor, selected!['time']!),
        math.max(neighbor, selected!['time']!),
      );
      selected!['$field.${dragPart}V'] = value.dy.clamp(spec.$2, spec.$3);
    }
    c.changed();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final object = c.selected;
      if (object?.id != framedObject) {
        framedObject = object?.id;
        selected = null;
        fit();
      }
      if (selected != null &&
          !(object?.keyframes.contains(selected) ?? false)) {
        selected = null;
      }
      return Focus(
        focusNode: focus,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.keyX) {
            remove();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.home) {
            setState(fit);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyI) {
            insert(c.cursor, object?.value(field, c.cursor) ?? 0);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: const Color(0xFF2A2C31),
              child: Row(
                children: [
                  const Icon(Icons.show_chart, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    object?.name ?? '选择声音对象',
                    style: const TextStyle(fontSize: 11, color: white),
                  ),
                  const SizedBox(width: 18),
                  DropdownButton<String>(
                    value: object?.modeFor(field) ?? 'smooth',
                    underline: const SizedBox(),
                    isDense: true,
                    style: const TextStyle(
                      fontSize: 11,
                      color: white,
                      fontFamily: 'Segoe UI',
                      fontFamilyFallback: ['Microsoft YaHei UI'],
                    ),
                    items: const [
                      DropdownMenuItem(value: 'bezier', child: Text('贝塞尔')),
                      DropdownMenuItem(value: 'smooth', child: Text('平滑')),
                      DropdownMenuItem(value: 'linear', child: Text('线性')),
                      DropdownMenuItem(value: 'step', child: Text('保持')),
                    ],
                    onChanged: object == null || c.busy
                        ? null
                        : (value) {
                            c.remember();
                            object.interpolationByField[field] = value!;
                            c.changed();
                          },
                  ),
                  const SizedBox(width: 12),
                  if (selected != null)
                    Text(
                      't ${selected!['time']!.toStringAsFixed(2)}  ·  ${selected![field]!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        color: muted,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: '插入曲线帧 I',
                    onPressed: object == null
                        ? null
                        : () => insert(c.cursor, object.value(field, c.cursor)),
                    icon: const Icon(Icons.add, size: 16),
                  ),
                  IconButton(
                    tooltip: '删除曲线帧 X',
                    onPressed: selected == null ? null : remove,
                    icon: const Icon(Icons.remove, size: 16),
                  ),
                  IconButton(
                    tooltip: '适配曲线 Home',
                    onPressed: () => setState(fit),
                    icon: const Icon(Icons.fit_screen, size: 16),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 156,
                    child: ListView(
                      children: curveChannels.entries
                          .map(
                            (entry) => InkWell(
                              onTap: () => setState(() {
                                field = entry.key;
                                selected = null;
                                fit();
                              }),
                              child: Container(
                                height: 29,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                color: field == entry.key
                                    ? const Color(0xFF364253)
                                    : panel,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: entry.value.$4,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      entry.value.$1,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: white,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (object?.keyframes.any(
                                          (k) => k.containsKey(entry.key),
                                        ) ??
                                        false)
                                      const Icon(
                                        Icons.diamond,
                                        size: 7,
                                        color: muted,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        plot = Rect.fromLTRB(
                          45,
                          10,
                          bounds.maxWidth - 16,
                          bounds.maxHeight - 24,
                        );
                        return Listener(
                          onPointerSignal: (event) {
                            if (event is PointerScrollEvent) {
                              final anchor = data(event.localPosition),
                                  factor = math
                                      .exp(event.scrollDelta.dy * .0015)
                                      .clamp(.7, 1.4);
                              setState(() {
                                minT = anchor.dx + (minT - anchor.dx) * factor;
                                maxT = math.max(
                                  minT + .05,
                                  anchor.dx + (maxT - anchor.dx) * factor,
                                );
                                minV = anchor.dy + (minV - anchor.dy) * factor;
                                maxV = math.max(
                                  minV + .001,
                                  anchor.dy + (maxV - anchor.dy) * factor,
                                );
                              });
                            }
                          },
                          onPointerMove: (event) {
                            if (event.buttons & kMiddleMouseButton != 0) {
                              setState(() {
                                final dt =
                                        -event.delta.dx /
                                        plot.width *
                                        (maxT - minT),
                                    dv =
                                        event.delta.dy /
                                        plot.height *
                                        (maxV - minV);
                                minT += dt;
                                maxT += dt;
                                minV += dv;
                                maxV += dv;
                              });
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (event) {
                              focus.requestFocus();
                              setState(() => pick(event.localPosition));
                              if (dragPart == null) {
                                c.seek(
                                  data(event.localPosition).dx
                                      .clamp(0, c.project.duration),
                                );
                              }
                            },
                            onDoubleTapDown: (event) => insert(
                              data(event.localPosition).dx,
                              data(event.localPosition).dy,
                            ),
                            onDoubleTap: () {},
                            onPanDown: (event) {
                              focus.requestFocus();
                              pick(event.localPosition);
                            },
                            onPanStart: (event) {
                              if (dragPart != null) {
                                c.remember();
                                dragTo(event.localPosition);
                              }
                            },
                            onPanUpdate: (event) {
                              if (dragPart == null) {
                                c.seek(
                                  data(event.localPosition).dx
                                      .clamp(0, c.project.duration),
                                );
                              } else {
                                dragTo(event.localPosition);
                              }
                            },
                            onPanEnd: (_) => dragPart = null,
                            child: CustomPaint(
                              key: const ValueKey('curve-canvas'),
                              size: Size.infinite,
                              painter: _CurvePainter(this, object),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _CurvePainter extends CustomPainter {
  final CurveEditorState editor;
  final SoundObject? object;
  _CurvePainter(this.editor, this.object);
  void text(Canvas c, String text, Offset at, {Color color = muted}) {
    final label = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: 'Consolas', fontSize: 9, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(c, at);
  }

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1B1D21));
    final r = editor.plot;
    if (r.width <= 0 || r.height <= 0) return;
    for (var i = 0; i <= 5; i++) {
      final x = r.left + r.width * i / 5, y = r.top + r.height * i / 5;
      c.drawLine(
        Offset(x, r.top),
        Offset(x, r.bottom),
        Paint()..color = line.withValues(alpha: .5),
      );
      c.drawLine(
        Offset(r.left, y),
        Offset(r.right, y),
        Paint()..color = line.withValues(alpha: .5),
      );
      text(
        c,
        (editor.minT + (editor.maxT - editor.minT) * i / 5).toStringAsFixed(1),
        Offset(x + 3, r.bottom + 6),
      );
      text(
        c,
        (editor.maxV - (editor.maxV - editor.minV) * i / 5).toStringAsFixed(2),
        Offset(4, y - 5),
      );
    }
    c.save();
    c.clipRect(r.inflate(3));
    if (object != null) {
      final color = curveChannels[editor.field]!.$4, path = Path();
      for (var x = 0.0; x <= r.width; x += 2) {
        final t = editor.minT + x / r.width * (editor.maxT - editor.minT);
        final at = editor.point(t, object!.value(editor.field, t));
        if (x == 0) {
          path.moveTo(at.dx, at.dy);
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }
      c.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );
      for (final key in editor.points) {
        final p = editor.point(key['time']!, key[editor.field]!);
        c.drawCircle(
          p,
          key == editor.selected ? 5 : 3.5,
          Paint()..color = key == editor.selected ? white : color,
        );
      }
      if (editor.selected != null &&
          object!.modeFor(editor.field) == 'bezier') {
        final p = editor.point(
          editor.selected!['time']!,
          editor.selected![editor.field]!,
        );
        for (final incoming in [true, false]) {
          final handle = editor.handle(editor.selected!, incoming);
          if (handle == null) continue;
          final h = editor.point(handle.dx, handle.dy);
          c.drawLine(p, h, Paint()..color = color.withValues(alpha: .65));
          c.drawRect(
            Rect.fromCenter(center: h, width: 7, height: 7),
            Paint()..color = const Color(0xFFE5B57A),
          );
        }
      }
    }
    final cursor = editor.point(editor.c.cursor, 0).dx;
    c.drawLine(
      Offset(cursor, r.top),
      Offset(cursor, r.bottom),
      Paint()
        ..color = accent
        ..strokeWidth = 1,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
