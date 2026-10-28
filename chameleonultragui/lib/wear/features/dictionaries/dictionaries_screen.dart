import 'dart:async';

import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_detail_page.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_download_page.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_selection.dart';
import 'package:chameleonultragui/wear/features/dictionaries/key_check_estimate.dart';
import 'package:chameleonultragui/wear/features/dictionaries/strings.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Key length (hex digits) used for Mifare Classic key checks.
const kMfcKeyHexLength = 12;

/// Compact switch that keeps a 48 dp tap target in a narrow row.
class DictSwitch extends StatelessWidget {
  const DictSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: WearMetrics.minTap,
    child: FittedBox(
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// List of dictionaries with per-dictionary "use for key checks" switches.
class DictionariesScreen extends StatefulWidget {
  const DictionariesScreen({super.key, this.httpClient});

  /// Injected HTTP client for the download page (tests).
  final http.Client? httpClient;

  @override
  State<DictionariesScreen> createState() => _DictionariesScreenState();
}

class _DictionariesScreenState extends State<DictionariesScreen> {
  List<Dictionary>? _dictionaries;
  Map<String, String> _folderPaths = {};
  Set<String>? _selected;
  StreamSubscription<void>? _sub;
  bool _started = false;

  WearServices get _services => WearServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _sub = _services.dictionaryStore.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final store = _services.dictionaryStore;
    final dicts = await store.getDictionaries();
    final folders = await store.getFolders();
    final selected = await WearDictionarySelection.selectedIds();
    if (!mounted) return;
    setState(() {
      _dictionaries = dicts;
      _folderPaths = _paths(folders);
      _selected = selected;
    });
  }

  static Map<String, String> _paths(List<DictionaryFolder> folders) {
    final byId = {for (final f in folders) f.id: f};
    String path(DictionaryFolder f) {
      final names = <String>[];
      var cur = f;
      final seen = <String>{};
      while (seen.add(cur.id)) {
        names.insert(0, cur.name);
        final parent = cur.parentId == null ? null : byId[cur.parentId];
        if (parent == null) break;
        cur = parent;
      }
      return names.join(' / ');
    }

    return {for (final f in folders) f.id: path(f)};
  }

  bool _isUsed(Dictionary d) => _selected == null || _selected!.contains(d.id);

  Future<void> _toggle(Dictionary d, bool used) async {
    final ids = await WearDictionarySelection.setUsed(
      d.id,
      used,
      all: _dictionaries ?? const [],
    );
    if (mounted) setState(() => _selected = ids);
  }

  Future<void> _useAll() async {
    await WearDictionarySelection.setSelectedIds(null);
    if (mounted) setState(() => _selected = null);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dicts = _dictionaries;
    if (dicts == null) {
      return const RoundScaffold(
        title: DictStrings.title,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final checked = WearDictionarySelection.resolve(
      dicts,
      _selected,
    ).where((d) => d.keyLength == kMfcKeyHexLength);
    final totalKeys = checked.fold<int>(0, (n, d) => n + d.keys.length);
    final estimate = estimateKeyCheck(totalKeys);
    final large = estimate >= kLargeCheckThreshold;

    // Sections: root first, then folders by path.
    final groups = <String, List<Dictionary>>{};
    for (final d in dicts) {
      final path = d.folderId == null ? '' : (_folderPaths[d.folderId] ?? '');
      groups.putIfAbsent(path, () => []).add(d);
    }
    final sections = groups.keys.toList()..sort();

    return RoundScaffold(
      title: DictStrings.title,
      children: [
        Center(
          child: StatusPill(
            label:
                '${DictStrings.total(totalKeys)} ${DictStrings.estimate(formatEstimate(estimate))}',
            kind: large ? StatusKind.warning : StatusKind.info,
            icon: large ? Icons.warning_amber_rounded : Icons.vpn_key_outlined,
          ),
        ),
        if (large)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              DictStrings.largeWarning,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: WearColors.warning,
              ),
            ),
          ),
        const SizedBox(height: 6),
        if (dicts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              DictStrings.empty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        for (final path in sections) ...[
          if (path.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                path,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: WearColors.muted,
                ),
              ),
            ),
          for (final d in groups[path]!)
            CompactListTile(
              title: d.name.isEmpty ? '(unnamed)' : d.name,
              subtitle:
                  '${DictStrings.keyCount(d.keys.length)} · ${DictStrings.keyBytes(d.keyLength)}',
              onTap: () => _open(DictionaryDetailPage(dictionaryId: d.id)),
              trailing: DictSwitch(
                value: _isUsed(d) && d.keyLength == kMfcKeyHexLength,
                onChanged: d.keyLength == kMfcKeyHexLength
                    ? (v) => _toggle(d, v)
                    : null,
              ),
            ),
        ],
        const SizedBox(height: 6),
        if (_selected != null)
          WearButton(
            label: DictStrings.useAll,
            style: WearButtonStyle.tonal,
            icon: Icons.select_all,
            onPressed: _useAll,
          ),
        WearButton(
          label: DictStrings.download,
          icon: Icons.download,
          onPressed: () =>
              _open(DictionaryDownloadPage(client: widget.httpClient)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            DictStrings.syncHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: WearColors.muted),
          ),
        ),
      ],
    );
  }
}
