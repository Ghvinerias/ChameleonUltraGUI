import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:flutter/material.dart';

/// Circular progress with optional centre content. [value] null = indeterminate.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    this.value,
    this.size = 120,
    this.strokeWidth = 10,
    this.color,
    this.child,
  });

  final double? value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: strokeWidth,
              color: WearColors.surface,
            ),
          ),
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value?.clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              color: c,
              backgroundColor: Colors.transparent,
            ),
          ),
          if (child != null)
            Padding(
              padding: EdgeInsets.all(strokeWidth + 6),
              child: Center(child: child),
            ),
        ],
      ),
    );
  }
}
