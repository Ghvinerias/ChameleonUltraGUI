import 'package:chameleonultragui/wear/theme/round_insets.dart';
import 'package:chameleonultragui/wear/widgets/round_list_view.dart';
import 'package:flutter/material.dart';

/// Page frame for the round screen. Pass [children] for a scrolling,
/// rotary-driven page, or [body] for fixed content (padded to the central
/// safe area). The [title] sits at the top and scrolls with the content.
class RoundScaffold extends StatelessWidget {
  const RoundScaffold({
    super.key,
    this.title,
    this.children,
    this.body,
    this.controller,
  }) : assert(
         (children == null) != (body == null),
         'Provide exactly one of children or body',
       );

  final String? title;
  final List<Widget>? children;
  final Widget? body;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = title == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          );
    return Scaffold(
      backgroundColor: Colors.black,
      body: children != null
          ? RoundListView(
              header: header,
              controller: controller,
              children: children!,
            )
          : Padding(
              padding: RoundInsets.fixed(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?header,
                  Expanded(child: body!),
                ],
              ),
            ),
    );
  }
}
