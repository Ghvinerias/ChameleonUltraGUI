import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:flutter/material.dart';

/// Ids of the home-menu entries, in display order.
enum WearDestinationId {
  read,
  slots,
  savedCards,
  dictionaries,
  device,
  sync,
  diagnostics;

  String label(AppLocalizations l) => switch (this) {
    read => l.wear_shell_read,
    slots => l.wear_shell_slots,
    savedCards => l.wear_shell_saved_cards,
    dictionaries => l.wear_shell_dictionaries,
    device => l.wear_shell_device,
    sync => l.wear_shell_sync,
    diagnostics => l.wear_shell_diagnostics,
  };

  IconData get icon => switch (this) {
    read => Icons.nfc,
    slots => Icons.grid_view,
    savedCards => Icons.credit_card,
    dictionaries => Icons.vpn_key_outlined,
    device => Icons.memory,
    sync => Icons.sync,
    diagnostics => Icons.bug_report_outlined,
  };
}

/// Registry of screens behind the home menu. Feature tracks call [register]
/// (from `wear_registrations.dart`) to replace the "coming soon" placeholder;
/// the shell itself never needs to change.
class WearDestinations {
  WearDestinations._();

  static final Map<WearDestinationId, WidgetBuilder> _builders = {};

  static void register(WearDestinationId id, WidgetBuilder builder) =>
      _builders[id] = builder;

  static bool isRegistered(WearDestinationId id) => _builders.containsKey(id);

  static WidgetBuilder builderFor(WearDestinationId id) =>
      _builders[id] ?? (ctx) => ComingSoonPage(id: id);

  /// Test helper.
  static void clear() => _builders.clear();
}

/// Placeholder shown for destinations without a registered screen.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.id});

  final WearDestinationId id;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return RoundScaffold(
      title: id.label(l),
      children: [
        Icon(id.icon, size: 36, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          l.wear_shell_coming_soon,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l.wear_shell_coming_soon_body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
