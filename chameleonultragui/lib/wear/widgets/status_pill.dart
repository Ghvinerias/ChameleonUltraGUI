import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:flutter/material.dart';

enum StatusKind { ok, warning, error, info, neutral }

/// Small rounded status label.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.kind = StatusKind.neutral,
    this.icon,
  });

  final String label;
  final StatusKind kind;
  final IconData? icon;

  static Color colorOf(StatusKind kind) => switch (kind) {
    StatusKind.ok => WearColors.ok,
    StatusKind.warning => WearColors.warning,
    StatusKind.error => WearColors.error,
    StatusKind.info => WearColors.info,
    StatusKind.neutral => WearColors.muted,
  };

  @override
  Widget build(BuildContext context) {
    final c = colorOf(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        border: Border.all(color: c, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: c, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
