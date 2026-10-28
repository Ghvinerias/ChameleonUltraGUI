import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionaries_screen.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_selection.dart';
import 'package:chameleonultragui/wear/features/dictionaries/strings.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// How many keys the detail page previews.
const kDetailPreviewKeys = 5;

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// Name, count, first keys (read-only), selection switch and delete.
class DictionaryDetailPage extends StatefulWidget {
  const DictionaryDetailPage({super.key, required this.dictionaryId});
  final String dictionaryId;

  @override
  State<DictionaryDetailPage> createState() => _DictionaryDetailPageState();
}

class _DictionaryDetailPageState extends State<DictionaryDetailPage> {
  Dictionary? _dictionary;
  Set<String>? _selected;
  bool _loaded = false;
  bool _started = false;

  WearServices get _services => WearServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final d = await _services.dictionaryStore.getDictionary(
      widget.dictionaryId,
    );
    final sel = await WearDictionarySelection.selectedIds();
    if (!mounted) return;
    setState(() {
      _dictionary = d;
      _selected = sel;
      _loaded = true;
    });
  }

  /// The system "empty" dictionary (id "") is built in and never deletable.
  bool get _builtIn => widget.dictionaryId.isEmpty;

  Future<void> _toggle(bool used) async {
    final all = await _services.dictionaryStore.getDictionaries();
    final ids = await WearDictionarySelection.setUsed(
      widget.dictionaryId,
      used,
      all: all,
    );
    if (mounted) setState(() => _selected = ids);
  }

  Future<void> _delete() async {
    final d = _dictionary!;
    final ok = await ConfirmDialog.show(
      context,
      title: DictStrings.deleteTitle,
      message: DictStrings.deleteMessage(d.name),
      confirmLabel: DictStrings.delete,
      cancelLabel: DictStrings.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    await _services.dictionaryStore.deleteDictionary(d.id);
    final sel = await WearDictionarySelection.selectedIds();
    if (sel != null && sel.remove(d.id)) {
      await WearDictionarySelection.setSelectedIds(sel);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _dictionary;
    if (!_loaded || d == null) {
      return RoundScaffold(
        title: DictStrings.title,
        body: Center(
          child: _loaded
              ? Text(DictStrings.noKeys, style: theme.textTheme.bodyMedium)
              : const CircularProgressIndicator(),
        ),
      );
    }
    final isMfc = d.keyLength == kMfcKeyHexLength;
    final used = _selected == null || _selected!.contains(d.id);
    final mono = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      letterSpacing: 0.5,
    );
    final preview = d.keys.take(kDetailPreviewKeys).toList();
    return RoundScaffold(
      title: d.name.isEmpty ? '(unnamed)' : d.name,
      children: [
        Text(
          '${DictStrings.keyCount(d.keys.length)} · ${DictStrings.keyBytes(d.keyLength)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: WearMetrics.minTap,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isMfc ? DictStrings.useForChecks : DictStrings.notForChecks,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              DictSwitch(
                value: used && isMfc,
                onChanged: isMfc ? _toggle : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          DictStrings.firstKeys,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(color: WearColors.muted),
        ),
        if (preview.isEmpty)
          Text(
            DictStrings.noKeys,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        for (final k in preview)
          Text(
            _hex(k),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono,
          ),
        const SizedBox(height: 8),
        if (_builtIn)
          Text(
            DictStrings.deleteBuiltIn,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: WearColors.muted),
          )
        else
          WearButton(
            label: DictStrings.delete,
            icon: Icons.delete_outline,
            style: WearButtonStyle.destructive,
            onPressed: _delete,
          ),
      ],
    );
  }
}
