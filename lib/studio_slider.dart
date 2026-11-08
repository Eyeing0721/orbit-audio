import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_style.dart';

/// Stable semantics avoid Material Slider's transient Windows accessibility nodes.
class StudioSlider extends StatelessWidget {
  final double value, min, max;
  final ValueChanged<double>? onChanged, onChangeStart;
  const StudioSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeStart,
  });
  void setFrom(double dx, double width) {
    const inset = material3 ? 8.0 : 4.0;
    onChanged?.call(
      (min + (max - min) * ((dx - inset) / (width - inset * 2)).clamp(0, 1))
          .clamp(min, max),
    );
  }

  void step(int direction) {
    if (onChanged == null) return;
    onChangeStart?.call(value);
    onChanged!((value + (max - min) / 100 * direction).clamp(min, max));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Semantics(
      slider: true,
      value: '${((value - min) / (max - min) * 100).round()}%',
      increasedValue:
          '${(((value - min) / (max - min) * 100) + 1).clamp(0, 100).round()}%',
      decreasedValue:
          '${(((value - min) / (max - min) * 100) - 1).clamp(0, 100).round()}%',
      onIncrease: onChanged == null ? null : () => step(1),
      onDecrease: onChanged == null ? null : () => step(-1),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              step(-1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              step(1);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: onChanged == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onChanged == null
                ? null
                : (e) {
                    onChangeStart?.call(value);
                    setFrom(e.localPosition.dx, bounds.maxWidth);
                  },
            onHorizontalDragStart: onChanged == null
                ? null
                : (_) => onChangeStart?.call(value),
            onHorizontalDragUpdate: onChanged == null
                ? null
                : (e) => setFrom(e.localPosition.dx, bounds.maxWidth),
            child: CustomPaint(
              size: Size(bounds.maxWidth, material3 ? 30 : 22),
              painter: _SliderPainter(
                ((value - min) / (max - min)).clamp(0, 1),
                onChanged != null,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SliderPainter extends CustomPainter {
  final double fraction;
  final bool enabled;
  final Color accent;
  _SliderPainter(this.fraction, this.enabled, this.accent);
  @override
  void paint(Canvas c, Size s) {
    if (material3) {
      const inset = 8.0, gap = 5.0;
      final y = s.height / 2, x = inset + (s.width - inset * 2) * fraction;
      final track = Paint()..color = const Color(0xFF454C5C);
      if (x + gap < s.width - inset) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x + gap, y - 4, s.width - inset, y + 4),
            const Radius.circular(4),
          ),
          track,
        );
      }
      if (x - gap > inset) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(inset, y - 4, x - gap, y + 4),
            const Radius.circular(4),
          ),
          Paint()..color = enabled ? accent : const Color(0xFF777D86),
        );
      }
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 4, height: 24),
          const Radius.circular(2),
        ),
        Paint()..color = enabled ? accent : const Color(0xFF777D86),
      );
      c.drawCircle(
        Offset(s.width - inset - 3, y),
        1.5,
        Paint()..color = const Color(0xFFBBC5D8),
      );
      return;
    }
    const inset = 4.0;
    final y = s.height / 2, x = inset + (s.width - inset * 2) * fraction;
    c.drawLine(
      Offset(inset, y),
      Offset(s.width - inset, y),
      Paint()
        ..color = const Color(0xFF45474D)
        ..strokeWidth = 3,
    );
    c.drawLine(
      Offset(inset, y),
      Offset(x, y),
      Paint()
        ..color = enabled ? accent : const Color(0xFF73777E)
        ..strokeWidth = 3,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: 5, height: 12),
        const Radius.circular(1),
      ),
      Paint()
        ..color = enabled ? const Color(0xFFC5CAD3) : const Color(0xFF777D86),
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.fraction != fraction ||
      old.enabled != enabled ||
      old.accent != accent;
}
