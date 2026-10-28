import 'dart:async';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/wear/features/saved_cards/card_detail_page.dart';
import 'package:chameleonultragui/wear/features/saved_cards/saved_cards_model.dart';
import 'package:chameleonultragui/wear/features/saved_cards/strings.dart';
import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/theme/round_insets.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Browsable list of the cards in the watch's store (works offline).
class SavedCardsPage extends StatefulWidget {
  const SavedCardsPage({super.key});

  @override
  State<SavedCardsPage> createState() => _SavedCardsPageState();
}

class _SavedCardsPageState extends State<SavedCardsPage> {
  final _scroll = ScrollController();
  StreamSubscription<Object?>? _changes;
  List<SavedRow>? _rows;
  Object? _error;
  bool _reloadQueued = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _changes = WearServicesScope.of(context).cardStore.changes
        .listen((_) => _queueReload());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Sync can emit one change per card; coalesce them into one reload.
  void _queueReload() {
    if (_reloadQueued) return;
    _reloadQueued = true;
    scheduleMicrotask(() {
      _reloadQueued = false;
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final store = WearServicesScope.of(context).cardStore;
    try {
      final cards = await store.getCards();
      final folders = await store.getFolders();
      final rows = buildSavedRows(cards, folders);
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _open(CardSave card) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => CardDetailPage(card: card)));

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (_error != null && rows == null) {
      return RoundScaffold(
        title: SavedCardsStrings.title,
        children: [
          const Text(SavedCardsStrings.loadFailed, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          WearButton(
            label: SavedCardsStrings.retry,
            onPressed: () {
              setState(() => _error = null);
              _load();
            },
          ),
        ],
      );
    }
    if (rows == null) {
      return const RoundScaffold(
        title: SavedCardsStrings.title,
        children: [Center(child: CircularProgressIndicator())],
      );
    }
    if (rows.isEmpty) {
      return RoundScaffold(
        title: SavedCardsStrings.emptyTitle,
        children: [
          Text(
            SavedCardsStrings.emptyBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: RotaryScrollable(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: RoundInsets.of(context, hasTitle: true),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  SavedCardsStrings.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              );
            }
            final row = rows[i - 1];
            return switch (row) {
              FolderHeaderRow(:final path) => _Header(
                path ?? SavedCardsStrings.unfiled,
              ),
              CardRow(:final card) => CompactListTile(
                title: cardDisplayName(card),
                subtitle: '${cardTypeLabel(card, l)}\n${card.uid}',
                leading: Icon(
                  isHighFrequency(card) ? Icons.nfc : Icons.waves,
                  color: card.color,
                ),
                onTap: () => _open(card),
              ),
            };
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2, left: 6, right: 6),
    child: Row(
      children: [
        const Icon(Icons.folder_outlined, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    ),
  );
}
