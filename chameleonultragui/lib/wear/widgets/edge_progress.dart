import 'dart:math' as math;

import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:flutter/material.dart';

/// Progress drawn as an arc along the edge of the round screen, starting at
/// the top and running clockwise. Leaves the whole safe square free for
/// content. [value] null = indeterminate (a short sweep that circles).
class EdgeProgress extends StatefulWidget {
  const EdgeProgress({
    super.key,
    this.value,
    this.strokeWidth = 5,
    this.color,
    this.animate = true,
  });

  final double? value;
  final double strokeWidth;
  final Color? color;

  /// False freezes the indeterminate sweep (tests that `pumpAndSettle`).
  final bool animate;

  @override
  State<EdgeProgress> createState() => _EdgeProgressState();
}

class _EdgeProgressState extends State<EdgeProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(EdgeProgress old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final spinning = widget.value == null && widget.animate;
    if (spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _EdgeProgressPainter(
              value: widget.value?.clamp(0.0, 1.0),
              spin: _spin.value,
              stroke: widget.strokeWidth,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeProgressPainter extends CustomPainter {
  _EdgeProgressPainter({
    required this.value,
    required this.spin,
    required this.stroke,
    required this.color,
  });

  final double? value;
  final double spin;
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side - stroke - 2,
      height: side - stroke - 2,
    );
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = WearColors.surface,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (value == null) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + spin * 2 * math.pi,
        math.pi / 3,
        false,
        paint,
      );
    } else if (value! > 0) {
      canvas.drawArc(rect, -math.pi / 2, value! * 2 * math.pi, false, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgeProgressPainter old) =>
      old.value != value ||
      old.spin != spin ||
      old.stroke != stroke ||
      old.color != color;
}
