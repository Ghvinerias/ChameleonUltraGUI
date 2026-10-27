import 'dart:math' as math;

import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:flutter/material.dart';

enum SlotState { empty, used, active }

/// 8 slots drawn as arcs on a ring, slot 0 starting at the top and running
/// clockwise. Tap an arc to get its index.
class SlotRing extends StatelessWidget {
  const SlotRing({
    super.key,
    required this.states,
    this.onSlotTap,
    this.size = 150,
    this.strokeWidth = 18,
    this.child,
  }) : assert(states.length == slotCount);

  static const int slotCount = 8;

  final List<SlotState> states;
  final ValueChanged<int>? onSlotTap;
  final double size;
  final double strokeWidth;
  final Widget? child;

  /// Slot index at [position] for a ring of [size], or null if the position is
  /// not on/near the ring band.
  static int? slotAt(Offset position, double size, double strokeWidth) {
    final c = Offset(size / 2, size / 2);
    final d = position - c;
    final r = d.distance;
    final outer = size / 2;
    // Generous: whole annulus plus the inner area band of one stroke width.
    if (r > outer + 4 || r < outer - strokeWidth * 2.2) return null;
    var a = math.atan2(d.dy, d.dx) + math.pi / 2; // 0 at top, clockwise
    a = (a % (2 * math.pi) + 2 * math.pi) % (2 * math.pi);
    return (a / (2 * math.pi / slotCount)).floor() % slotCount;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onSlotTap == null
            ? null
            : (d) {
                final i = slotAt(d.localPosition, size, strokeWidth);
                if (i != null) onSlotTap!(i);
              },
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _SlotRingPainter(states, strokeWidth, scheme.primary),
            ),
            if (child != null)
              Padding(
                padding: EdgeInsets.all(strokeWidth + 10),
                child: Center(child: child),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlotRingPainter extends CustomPainter {
  _SlotRingPainter(this.states, this.stroke, this.primary);

  final List<SlotState> states;
  final double stroke;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    const n = SlotRing.slotCount;
    const sweep = 2 * math.pi / n;
    const gap = 0.12;
    for (var i = 0; i < n; i++) {
      final s = states[i];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s == SlotState.active ? stroke : stroke * 0.7
        ..strokeCap = StrokeCap.butt
        ..color = switch (s) {
          SlotState.active => primary,
          SlotState.used => WearColors.info,
          SlotState.empty => const Color(0xFF3A3D42),
        };
      final start = -math.pi / 2 + i * sweep + gap / 2;
      canvas.drawArc(rect, start, sweep - gap, false, paint);
    }
  }

  @override
  bool shouldRepaint(_SlotRingPainter old) =>
      old.states != states || old.stroke != stroke || old.primary != primary;
}
