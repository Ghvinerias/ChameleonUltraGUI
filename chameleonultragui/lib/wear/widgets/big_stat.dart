import 'package:flutter/material.dart';

/// Large figure with a caption underneath: the centre of a progress screen
/// (the progress itself runs along the screen edge, see `EdgeProgress`).
class BigStat extends StatelessWidget {
  const BigStat(this.value, this.caption, {super.key});

  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 30,
              height: 1.1,
            ),
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}
