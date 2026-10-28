import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sync/ui/strings.dart';
import 'package:chameleonultragui/sync/ui/watch_sync_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings entry (developer mode, Android) that opens the watch sync page.
class WatchSyncTile extends StatelessWidget {
  const WatchSyncTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.sync),
      title: const Text(SyncStrings.phoneEntryTitle),
      subtitle: const Text(SyncStrings.phoneEntrySubtitle),
      onTap: () {
        final prefs = context
            .read<ChameleonGUIState>()
            .sharedPreferencesProvider;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WatchSyncPage(
              cards: prefs.cardStore,
              dictionaries: prefs.dictionaryStore,
            ),
          ),
        );
      },
    );
  }
}
