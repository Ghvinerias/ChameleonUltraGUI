import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/wear/features/saved_cards/load_to_slot_page.dart';
import 'package:chameleonultragui/wear/features/saved_cards/rename_page.dart';
import 'package:chameleonultragui/wear/features/saved_cards/saved_cards_model.dart';
import 'package:chameleonultragui/wear/features/saved_cards/strings.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Summary of one saved card and its actions (load, rename, delete).
class CardDetailPage extends StatefulWidget {
  const CardDetailPage({super.key, required this.card});

  final CardSave card;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  late CardSave _card = widget.card;
  bool _busy = false;

  Future<void> _rename() async {
    final store = WearServicesScope.of(context).cardStore;
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RenameCardPage(initialName: _card.name),
      ),
    );
    if (name == null || name == _card.name || !mounted) return;
    final fresh = await store.getCard(_card.id) ?? _card;
    fresh.name = name;
    final saved = await store.saveCard(fresh);
    if (mounted) setState(() => _card = saved);
  }

  Future<void> _delete() async {
    if (_busy) return;
    final store = WearServicesScope.of(context).cardStore;
    final ok = await ConfirmDialog.show(
      context,
      title: SavedCardsStrings.deleteTitle,
      message: SavedCardsStrings.deleteBody(cardDisplayName(_card)),
      confirmLabel: SavedCardsStrings.delete,
      cancelLabel: SavedCardsStrings.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    _busy = true;
    await store.deleteCard(_card.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _load() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WearConnectionGate(
        builder: (context, device) => LoadToSlotPage(card: _card),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final services = WearServicesScope.of(context);
    final canLoad =
        services.slotService?.canUpload(_card) ?? cardTypeLoadable(_card.tag);
    final summary = dumpSummary(_card);
    return RoundScaffold(
      title: cardDisplayName(_card),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              key: const Key('cardColorChip'),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _card.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                cardTypeLabel(_card, l),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Info(SavedCardsStrings.uid, _card.uid),
        if (_card.atqa.isNotEmpty)
          _Info(SavedCardsStrings.atqa, hexBytes(_card.atqa)),
        if (isHighFrequency(_card))
          _Info(SavedCardsStrings.sak, hexBytes([_card.sak])),
        if (_card.ats.isNotEmpty)
          _Info(SavedCardsStrings.ats, hexBytes(_card.ats)),
        if (summary != null) _Info(SavedCardsStrings.dump, summary),
        const SizedBox(height: 8),
        WearButton(
          label: SavedCardsStrings.loadIntoSlot,
          icon: Icons.upload,
          onPressed: canLoad ? _load : null,
        ),
        if (!canLoad)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              SavedCardsStrings.cannotLoad,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        WearButton(
          label: SavedCardsStrings.rename,
          icon: Icons.edit,
          style: WearButtonStyle.tonal,
          onPressed: _rename,
        ),
        WearButton(
          label: SavedCardsStrings.delete,
          icon: Icons.delete_outline,
          style: WearButtonStyle.destructive,
          onPressed: _delete,
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: theme.textTheme.bodySmall),
            TextSpan(text: value, style: theme.textTheme.bodyMedium),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
