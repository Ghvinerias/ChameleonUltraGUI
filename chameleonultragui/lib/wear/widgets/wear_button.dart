import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:flutter/material.dart';

enum WearButtonStyle { filled, tonal, destructive }

/// Full-width pill button, 48 dp tall minimum.
class WearButton extends StatelessWidget {
  const WearButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = WearButtonStyle.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final WearButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (style) {
      WearButtonStyle.filled => (scheme.primary, scheme.onPrimary),
      WearButtonStyle.tonal => (WearColors.surface, scheme.onSurface),
      WearButtonStyle.destructive => (WearColors.error, Colors.black),
    };
    final text = Text(
      label,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(WearMetrics.minTap),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: const StadiumBorder(),
        ),
        child: icon == null
            ? text
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Flexible(child: text),
                ],
              ),
      ),
    );
  }
}
