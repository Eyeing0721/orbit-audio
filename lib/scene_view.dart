import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'studio_style.dart';

class SceneView extends StatefulWidget {
  final AudioProject project;
  final String? selectedId;
  final double time;
  final void Function(String) onSelect;
  final void Function(String, double, double, double) onMove;
  final VoidCallback onBeginEdit;
  final bool moving;
  final String moveAxis;
  final VoidCallback? onConfirmMove, onCancelMove;
  final void Function(String)? onConstrainMove;
  final void Function(Offset?, bool)? onPointerPosition;
  const SceneView({
    super.key,
    required this.project,
    required this.selectedId,
    required this.time,
    required this.onSelect,
    required this.onMove,
    required this.onBeginEdit,
    this.moving = false,
    this.moveAxis = 'XY',
    this.onConfirmMove,
    this.onCancelMove,
    this.onConstrainMove,
    this.onPointerPosition,
  });
  @override
  State<SceneView> createState() => SceneViewState();
}

class SceneViewState extends State<SceneView> {
  double yaw = -.48, elevation = .64, scale = 42;
  String view = 'perspective', axis = 'XY';
  String? dragging;
  Offset pan = Offset.zero;
  Offset? _pointer, _moveStart;
  List<double>? _origin;
  int? _cameraPointer;
  Size canvas = Size.zero;
  SceneProjection get projection =>
      SceneProjection(canvas, scale, yaw, elevation, view, pan: pan);
  @override
  void didUpdateWidget(SceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.moving &&
        (!oldWidget.moving || oldWidget.selectedId != widget.selectedId)) {
      _captureMove();
    }
    if (!widget.moving) {
      _origin = null;
      _moveStart = null;
    }
  }

  void _captureMove() {
    final object = widget.project.objects
        .where((o) => o.id == widget.selectedId)
        .firstOrNull;
    if (object == null) return;
    _origin = [
      object.value('x', widget.time),
      object.value('y', widget.time),
      object.value('z', widget.time),
    ];
    _moveStart = _pointer ?? projection.center;
  }

  void _report(Offset point, bool inside) {
    _pointer = point;
    widget.onPointerPosition?.call(projection.groundAt(point), inside);
  }

  void _moveTo(Offset point) {
    if (!widget.moving || _origin == null || _moveStart == null) return;
    final delta =
        (point - _moveStart!) *
        (HardwareKeyboard.instance.isShiftPressed ? .1 : 1);
    var dx = 0.0, dy = 0.0, dz = 0.0;
    if (widget.moveAxis == 'XY') {
      final change = projection.unprojectDelta(delta);
      dx = change.dx;
      dy = change.dy;
    } else {
      final vector =
          projection.project(
            widget.moveAxis == 'X' ? 1 : 0,
            widget.moveAxis == 'Y' ? 1 : 0,
            widget.moveAxis == 'Z' ? 1 : 0,
          ) -
          projection.project(0, 0, 0);
      final amount = vector.distanceSquared < .001
          ? 0.0
          : (delta.dx * vector.dx + delta.dy * vector.dy) /
                vector.distanceSquared;
      if (widget.moveAxis == 'X') dx = amount;
      if (widget.moveAxis == 'Y') dy = amount;
      if (widget.moveAxis == 'Z') dz = amount;
    }
    widget.onMove(
      widget.selectedId!,
      _origin![0] + dx,
      _origin![1] + dy,
      _origin![2] + dz,
    );
  }

  void setView(String value) {
    setState(() => view = value);
    if (_pointer != null) _report(_pointer!, true);
  }

  void resetView() => setState(() {
    yaw = -.48;
    elevation = .64;
    scale = 42;
    pan = Offset.zero;
  });
  void frameSelected() {
    final object = widget.project.objects
        .where((o) => o.id == widget.selectedId)
        .firstOrNull;
    if (object == null) {
      resetView();
      return;
    }
    final at = projection.project(
      object.value('x', widget.time),
      object.value('y', widget.time),
      object.value('z', widget.time),
    );
    setState(() => pan += Offset(canvas.width * .5, canvas.height * .55) - at);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bounds) {
        canvas = Size(bounds.maxWidth, bounds.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: MouseRegion(
                onEnter: (event) => _report(event.localPosition, true),
                onExit: (event) => widget.onPointerPosition?.call(
                  projection.groundAt(event.localPosition),
                  false,
                ),
                onHover: (event) {
                  _report(event.localPosition, true);
                  _moveTo(event.localPosition);
                },
                cursor: widget.moving
                    ? SystemMouseCursors.move
                    : SystemMouseCursors.basic,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _report(event.localPosition, true);
                    if (event.buttons & kMiddleMouseButton != 0) {
                      _cameraPointer = event.pointer;
                      return;
                    }
                    if (event.buttons & kSecondaryMouseButton != 0 &&
                        widget.moving) {
                      widget.onCancelMove?.call();
                      return;
                    }
                    if (event.buttons & kPrimaryMouseButton != 0) {
                      if (widget.moving) {
                        widget.onConfirmMove?.call();
                        return;
                      }
                      final hit = _hit(event.localPosition);
                      if (hit != null) widget.onSelect(hit);
                    }
                  },
                  onPointerMove: (event) {
                    _report(event.localPosition, true);
                    if (event.pointer == _cameraPointer) {
                      setState(() {
                        if (HardwareKeyboard.instance.isShiftPressed) {
                          pan += event.delta;
                        } else if (HardwareKeyboard.instance.isAltPressed) {
                          scale =
                              (scale *
                                      math.exp(
                                        (event.delta.dx - event.delta.dy) *
                                            .008,
                                      ))
                                  .clamp(18, 100);
                        } else if (view == 'perspective') {
                          yaw += event.delta.dx * .008;
                          elevation = (elevation + event.delta.dy * .006).clamp(
                            .18,
                            1.4,
                          );
                        }
                      });
                      _report(event.localPosition, true);
                    } else {
                      _moveTo(event.localPosition);
                    }
                  },
                  onPointerUp: (event) {
                    if (event.pointer == _cameraPointer) {
                      _cameraPointer = null;
                      if (widget.moving) _captureMove();
                    }
                  },
                  onPointerCancel: (event) {
                    if (event.pointer == _cameraPointer) _cameraPointer = null;
                  },
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      setState(
                        () => scale = (scale - event.scrollDelta.dy * .08)
                            .clamp(18, 100),
                      );
                      _report(event.localPosition, true);
                    }
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: ScenePainter(
                      widget.project,
                      widget.selectedId,
                      widget.time,
                      projection,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    material3 ? '空间声场' : 'SPATIAL VIEW',
                    style: TextStyle(
                      fontSize: material3 ? 16 : 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: material3 ? .2 : 2,
                      color: Color(0xFF979BA3),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    view == 'right'
                        ? '右视 · YZ 平面'
                        : view == 'top'
                        ? '俯视 · XY 平面'
                        : view == 'front'
                        ? '正视 · XZ 平面'
                        : '透视 · 三维声场',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCCD0D7),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: bounds.maxWidth < 540
                  ? PopupMenuButton<String>(
                      tooltip: '切换声场视图',
                      onSelected: setView,
                      icon: const Icon(Icons.view_in_ar, size: 19),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'perspective', child: Text('透视')),
                        PopupMenuItem(value: 'top', child: Text('俯视')),
                        PopupMenuItem(value: 'front', child: Text('正视')),
                        PopupMenuItem(value: 'right', child: Text('右视')),
                      ],
                    )
                  : material3
                  ? SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'perspective', label: Text('透视')),
                        ButtonSegment(value: 'top', label: Text('俯视')),
                        ButtonSegment(value: 'front', label: Text('正视')),
                        ButtonSegment(value: 'right', label: Text('右视')),
                      ],
                      selected: {view},
                      onSelectionChanged: (selection) =>
                          setView(selection.single),
                    )
                  : Row(
                      children: [
                        _viewButton('透视', 'perspective'),
                        _viewButton('俯视', 'top'),
                        _viewButton('正视', 'front'),
                      ],
                    ),
            ),
            Positioned(
              bottom: 16,
              left: 18,
              child: Row(
                children: [
                  if (material3)
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'XY', label: Text('XY 移动')),
                        ButtonSegment(value: 'Z', label: Text('Z 高度')),
                      ],
                      selected: {widget.moveAxis == 'Z' ? 'Z' : 'XY'},
                      onSelectionChanged: widget.moving
                          ? (selection) =>
                                widget.onConstrainMove?.call(selection.single)
                          : null,
                    )
                  else ...[
                    _axisButton('XY'),
                    _axisButton('Z'),
                  ],
                  const SizedBox(width: 12),
                  if (bounds.maxWidth > 590)
                    const Text(
                      '左键选择 · G 移动 · 中键旋转',
                      style: TextStyle(fontSize: 10, color: Color(0xFF858B94)),
                    ),
                ],
              ),
            ),
            if (bounds.maxWidth >= 400)
              Positioned(
                bottom: 16,
                right: 18,
                child: Text(
                  '${(scale / 42).toStringAsFixed(1)}×  /  METRES',
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: Color(0xFF898F99),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _viewButton(String label, String key) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: Tooltip(
      message: '切换$label视图',
      child: InkWell(
        onTap: () => setState(() => view = key),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: view == key
                ? const Color(0xFF3A3F47)
                : const Color(0xFF292B30),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: view == key
                  ? const Color(0xFF586574)
                  : const Color(0xFF41444A),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: view == key
                  ? const Color(0xFFB1C9E0)
                  : const Color(0xFFA3A8B1),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _axisButton(String a) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: InkWell(
      onTap: () => setState(() => axis = a),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: axis == a ? const Color(0xFF3A3E45) : const Color(0xFF292B2F),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          a == 'Z' ? 'Z 高度' : 'XY 移动',
          style: TextStyle(
            fontSize: 10,
            color: axis == a
                ? const Color(0xFFB1C9E0)
                : const Color(0xFF969CA6),
          ),
        ),
      ),
    ),
  );
  String? _hit(Offset location) {
    String? found;
    var nearest = 28.0;
    for (final obj in widget.project.objects) {
      final point = projection.project(
        obj.value('x', widget.time),
        obj.value('y', widget.time),
        obj.value('z', widget.time),
      );
      final d = (point - location).distance;
      if (d < nearest) {
        found = obj.id;
        nearest = d;
      }
    }
    return found;
  }
}

class SceneProjection {
  final Size size;
  final double scale, yaw, elevation;
  final String view;
  final Offset pan;
  SceneProjection(
    this.size,
    this.scale,
    this.yaw,
    this.elevation,
    this.view, {
    this.pan = Offset.zero,
  });
  Offset get center => Offset(size.width * .5, size.height * .55) + pan;
  Offset? groundAt(Offset point) => view == 'front' || view == 'right'
      ? null
      : unprojectDelta(point - center);
  Offset project(double x, double y, double z) {
    if (view == 'top') return center + Offset(x * scale, -y * scale);
    if (view == 'front') return center + Offset(x * scale, -z * scale);
    if (view == 'right') return center + Offset(y * scale, -z * scale);
    final u = x * math.cos(yaw) - y * math.sin(yaw);
    final v = x * math.sin(yaw) + y * math.cos(yaw);
    return center +
        Offset(
          u * scale,
          -v * scale * math.sin(elevation) - z * scale * math.cos(elevation),
        );
  }

  Offset unprojectDelta(Offset delta) {
    if (view == 'top') return Offset(delta.dx / scale, -delta.dy / scale);
    if (view == 'front') return Offset(delta.dx / scale, 0);
    if (view == 'right') return Offset(0, delta.dx / scale);
    final u = delta.dx / scale, v = -delta.dy / (scale * math.sin(elevation));
    return Offset(
      u * math.cos(yaw) + v * math.sin(yaw),
      -u * math.sin(yaw) + v * math.cos(yaw),
    );
  }
}

class ScenePainter extends CustomPainter {
  final AudioProject project;
  final String? selected;
  final double time;
  final SceneProjection p;
  ScenePainter(this.project, this.selected, this.time, this.p);
  void label(
    Canvas c,
    String text,
    Offset at,
    Color color, {
    double size = 11,
    FontWeight weight = FontWeight.normal,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: const ['Microsoft YaHei UI', 'Microsoft YaHei'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(material3 ? 0xFF1B1C20 : 0xFF222326),
    );
    final bg = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0xFF2A2C30), Color(0x00222326)],
        radius: .72,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final grid = Paint()..strokeWidth = .65;
    for (var i = -12; i <= 12; i++) {
      grid.color = i % 4 == 0
          ? const Color(0xFF3B3E44)
          : const Color(0xFF303237);
      canvas.drawLine(
        p.project(i.toDouble(), -12, 0),
        p.project(i.toDouble(), 12, 0),
        grid,
      );
      canvas.drawLine(
        p.project(-12, i.toDouble(), 0),
        p.project(12, i.toDouble(), 0),
        grid,
      );
    }
    final center = p.project(0, 0, 0);
    for (final radius in [2.0, 4.0, 6.0, 8.0]) {
      final path = Path();
      for (var i = 0; i <= 100; i++) {
        final a = i / 100 * math.pi * 2;
        final q = p.project(math.cos(a) * radius, math.sin(a) * radius, 0);
        if (i == 0) {
          path.moveTo(q.dx, q.dy);
        } else {
          path.lineTo(q.dx, q.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF4B4E55).withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7,
      );
    }
    label(
      canvas,
      'FRONT',
      p.project(0, 6.5, 0) + const Offset(-18, -14),
      const Color(0xFF858D99),
      size: 10,
      weight: FontWeight.w600,
    );
    label(
      canvas,
      'REAR',
      p.project(0, -6.5, 0) + const Offset(-14, 5),
      const Color(0xFF737A85),
      size: 10,
    );
    label(canvas, 'L', p.project(-7, 0, 0), const Color(0xFF737A85), size: 10);
    label(canvas, 'R', p.project(7, 0, 0), const Color(0xFF737A85), size: 10);
    // The head's orientation matches the renderer: positive yaw turns to the right.
    final yaw = project.listener['yaw']! * math.pi / 180;
    final head = p.project(
      project.listener['x']!,
      project.listener['y']!,
      project.listener['z']!,
    );
    final direction =
        p.project(math.sin(yaw) * 1.3, math.cos(yaw) * 1.3, 0) - center;
    final cone = Path()
      ..moveTo(head.dx, head.dy)
      ..lineTo(head.dx + direction.dx - 24, head.dy + direction.dy - 10)
      ..lineTo(head.dx + direction.dx + 24, head.dy + direction.dy - 10)
      ..close();
    canvas.drawPath(
      cone,
      Paint()..color = const Color(0xFFA3B5CC).withValues(alpha: .05),
    );
    canvas.drawCircle(head, 20, Paint()..color = const Color(0xFF303238));
    canvas.drawCircle(
      head,
      20,
      Paint()
        ..color = const Color(0xFF9CA5B2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: head, width: 17, height: 20),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFFAFB7C2),
    );
    canvas.drawLine(
      head + const Offset(-13, -5),
      head + const Offset(-13, 6),
      Paint()
        ..color = const Color(0xFFAFB7C2)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      head + const Offset(13, -5),
      head + const Offset(13, 6),
      Paint()
        ..color = const Color(0xFFAFB7C2)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      head + const Offset(0, -4),
      3,
      Paint()..color = const Color(0xFF30343B),
    );
    label(
      canvas,
      'LISTENER',
      head + const Offset(-25, 29),
      const Color(0xFF9BA5B3),
      size: 9,
      weight: FontWeight.w600,
    );
    for (final obj in project.objects) {
      final isSelected = obj.id == selected,
          color = obj.mute ? const Color(0xFF69717D) : obj.color;
      final x = obj.value('x', time),
          y = obj.value('y', time),
          z = obj.value('z', time);
      final at = p.project(x, y, z), floor = p.project(x, y, 0);
      if (obj.keyframes.length > 1) {
        final path = Path();
        final start = obj.keyframes.first['time']!,
            end = obj.keyframes.last['time']!;
        for (var j = 0; j <= 70; j++) {
          final t = start + (end - start) * j / 70;
          final pt = p.project(
            obj.value('x', t),
            obj.value('y', t),
            obj.value('z', t),
          );
          if (j == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: isSelected ? 0.48 : .15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
        for (final key in obj.keyframes) {
          final pt = p.project(key['x'] ?? x, key['y'] ?? y, key['z'] ?? z);
          canvas.drawCircle(
            pt,
            3,
            Paint()..color = color.withValues(alpha: .6),
          );
        }
      }
      canvas.drawOval(
        Rect.fromCenter(center: floor, width: 20, height: 8),
        Paint()..color = color.withValues(alpha: .14),
      );
      canvas.drawLine(
        floor,
        at,
        Paint()
          ..color = color.withValues(alpha: .35)
          ..strokeWidth = 1,
      );
      if (isSelected) {
        canvas.drawCircle(
          at,
          29,
          Paint()..color = color.withValues(alpha: .08),
        );
        canvas.drawCircle(
          at,
          23,
          Paint()
            ..color = color.withValues(alpha: .5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      canvas.drawCircle(
        at,
        15,
        Paint()..color = Color.lerp(const Color(0xFF2B2E34), color, .16)!,
      );
      canvas.drawCircle(
        at,
        15,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.8 : 1.1,
      );
      final icon = obj.generator.isNotEmpty
          ? Icons.water_drop_outlined
          : obj.kind == 'vocals'
          ? Icons.mic_none
          : Icons.graphic_eq;
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: color,
            fontSize: 17,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
      label(
        canvas,
        obj.name,
        at + const Offset(22, -9),
        color,
        size: 11,
        weight: isSelected ? FontWeight.w600 : FontWeight.normal,
      );
      if (isSelected) {
        label(
          canvas,
          '${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, ${z.toStringAsFixed(1)} m',
          at + const Offset(23, 8),
          const Color(0xFF919AA7),
          size: 9,
        );
        final axes = [
          (p.project(x + 1.1, y, z), const Color(0xFFE67B74), 'X'),
          (p.project(x, y + 1.1, z), const Color(0xFF8DC779), 'Y'),
          (p.project(x, y, z + 1.1), const Color(0xFF7EAFE8), 'Z'),
        ];
        for (final (tip, c, text) in axes) {
          canvas.drawLine(
            at,
            tip,
            Paint()
              ..color = c
              ..strokeWidth = 1.4,
          );
          canvas.drawCircle(tip, 3, Paint()..color = c);
          label(canvas, text, tip + const Offset(5, -9), c, size: 9);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter old) => true;
}
