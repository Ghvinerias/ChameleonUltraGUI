import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/wear/navigation/wear_destinations.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:flutter/material.dart';

/// Home menu: one tile per [WearDestinationId].
class WearHomePage extends StatelessWidget {
  const WearHomePage({super.key, this.extraEntries = const []});

  /// Additional tiles appended after the standard entries (e.g. the gallery).
  final List<Widget> extraEntries;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return RoundScaffold(
      title: l.wear_shell_home_title,
      children: [
        for (final id in WearDestinationId.values)
          CompactListTile(
            key: ValueKey('home-${id.name}'),
            title: id.label(l),
            leading: Icon(id.icon),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: WearDestinations.builderFor(id))),
          ),
        ...extraEntries,
      ],
    );
  }
}
