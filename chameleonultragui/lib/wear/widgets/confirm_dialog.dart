import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Full-screen confirmation page. Swiping back (system gesture) dismisses it
/// and counts as "cancel". Use [ConfirmDialog.show].
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.confirmLabel,
    this.cancelLabel,
    this.destructive = false,
  });

  final String title;
  final String? message;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool destructive;

  /// Resolves to true only when the user confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
  }) async {
    final r = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          destructive: destructive,
        ),
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return RoundScaffold(
      title: title,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        WearButton(
          label: confirmLabel ?? l.wear_shell_confirm,
          style: destructive
              ? WearButtonStyle.destructive
              : WearButtonStyle.filled,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        WearButton(
          label: cancelLabel ?? l.wear_shell_cancel,
          style: WearButtonStyle.tonal,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
