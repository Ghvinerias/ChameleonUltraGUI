import 'package:flutter/material.dart';

import '../watch_installer.dart';
import 'strings.dart';

/// Error card with a human hint per [WatchInstallErrorType].
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error, this.action});
  final WatchInstallException error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              InstallerStrings.errorTitle(error.type),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 6),
            Text(
              InstallerStrings.errorHint(error.type),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            if (error.message != null && error.message!.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(
                error.message!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: scheme.onErrorContainer,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
