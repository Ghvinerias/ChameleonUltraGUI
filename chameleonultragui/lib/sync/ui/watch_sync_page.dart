import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_engine.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/ui/strings.dart';
import 'package:chameleonultragui/sync/ui/sync_check.dart';
import 'package:chameleonultragui/sync/ui/sync_controller.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mirrorPrefKey = 'wear_sync_mirror_dictionaries';

/// Phone page: sync with the watch, plus the link check.
class WatchSyncPage extends StatefulWidget {
  const WatchSyncPage({
    super.key,
    required this.cards,
    required this.dictionaries,
    this.linkFactory = openWearSyncLink,
    this.options = const SyncOptions(),
    this.initialMirror,
    this.onMirrorChanged,
    this.checkPayloadBytes = 1024 * 1024,
    this.checkTransferTimeout = const Duration(seconds: 30),
  });

  final CardStore cards;
  final DictionaryStore dictionaries;
  final SyncLinkFactory linkFactory;
  final SyncOptions options;

  /// Mirror switch value. When null it is read from (and saved to)
  /// SharedPreferences.
  final bool? initialMirror;
  final void Function(bool)? onMirrorChanged;
  final int checkPayloadBytes;
  final Duration checkTransferTimeout;

  @override
  State<WatchSyncPage> createState() => _WatchSyncPageState();
}

class _WatchSyncPageState extends State<WatchSyncPage> {
  late final SyncUiController _c;

  @override
  void initState() {
    super.initState();
    _c = SyncUiController(
      role: SyncRole.phone,
      linkFactory: widget.linkFactory,
      cards: widget.cards,
      dictionaries: widget.dictionaries,
      options: widget.options,
      mirrorDictionaries: widget.initialMirror ?? false,
      onMirrorChanged: (v) {
        widget.onMirrorChanged?.call(v);
        if (widget.initialMirror == null) _saveMirror(v);
      },
      checkPayloadBytes: widget.checkPayloadBytes,
      checkTransferTimeout: widget.checkTransferTimeout,
    );
    if (widget.initialMirror == null) _loadMirror();
    _c.start();
  }

  Future<void> _loadMirror() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) _c.setMirror(p.getBool(_mirrorPrefKey) ?? false);
    } catch (_) {}
  }

  Future<void> _saveMirror(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_mirrorPrefKey, v);
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(SyncStrings.phonePageTitle)),
    body: ListenableBuilder(
      listenable: _c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(context),
          if (_c.availability != SyncAvailability.unsupported &&
              _c.availability != SyncAvailability.starting) ...[
            const SizedBox(height: 12),
            _syncCard(context),
            const SizedBox(height: 12),
            _libraryCard(context),
            if (_c.lastReport != null || _c.lastError != null) ...[
              const SizedBox(height: 12),
              _resultCard(context),
            ],
            const SizedBox(height: 12),
            _checkCard(context),
          ],
        ],
      ),
    ),
  );

  Widget _statusCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, title, body) = switch (_c.availability) {
      SyncAvailability.starting => (
        Icons.hourglass_empty,
        scheme.outline,
        SyncStrings.peerStarting,
        null,
      ),
      SyncAvailability.unsupported => (
        Icons.sync_disabled,
        scheme.error,
        SyncStrings.unsupportedTitle(_c.unsupported!),
        SyncStrings.unsupportedBody(_c.unsupported!),
      ),
      SyncAvailability.peerUnavailable => (
        Icons.watch_off_outlined,
        scheme.error,
        SyncStrings.peerUnavailable,
        SyncStrings.peerUnavailableHintPhone,
      ),
      SyncAvailability.peerAvailable => (
        Icons.watch,
        Colors.green,
        SyncStrings.peerAvailablePhone,
        null,
      ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, key: const Key('sync-status')),
        subtitle: body == null ? null : Text(body),
      ),
    );
  }

  Widget _syncCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('sync-mirror'),
              contentPadding: EdgeInsets.zero,
              title: const Text(SyncStrings.mirrorTitle),
              subtitle: const Text(SyncStrings.mirrorSubtitle),
              value: _c.mirrorDictionaries,
              onChanged: _c.running ? null : _c.setMirror,
            ),
            const SizedBox(height: 8),
            if (_c.running) ...[
              Text(
                SyncStrings.phaseLabel(_c.phase ?? SyncPhase.connecting),
                key: const Key('sync-phase'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                key: const Key('sync-progress'),
                value: _c.progress,
              ),
              const SizedBox(height: 4),
              Text(
                '${SyncStrings.bytes(_c.bytesTransferred)} / '
                '${SyncStrings.bytes(_c.bytesTotal)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('sync-cancel'),
                onPressed: _c.cancel,
                child: const Text(SyncStrings.cancel),
              ),
            ] else ...[
              FilledButton.icon(
                key: const Key('sync-now'),
                onPressed: _c.canSyncNow ? _c.syncNow : null,
                icon: const Icon(Icons.sync),
                label: const Text(SyncStrings.syncNow),
              ),
              const SizedBox(height: 8),
              Text(SyncStrings.phoneHowTo, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _libraryCard(BuildContext context) => Card(
    child: ListTile(
      title: const Text(SyncStrings.libraryTitle),
      subtitle: Text(
        [
          for (final k in SyncEntityKind.values)
            '${SyncStrings.kindLabel(k)}: ${_c.libraryCounts[k] ?? 0}',
        ].join('\n'),
        key: const Key('sync-library'),
      ),
    ),
  );

  Widget _resultCard(BuildContext context) {
    final theme = Theme.of(context);
    final err = _c.lastError;
    if (err != null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text(SyncStrings.lastFailureTitle),
          subtitle: Text(
            SyncStrings.errorMessage(err),
            key: const Key('sync-error'),
          ),
        ),
      );
    }
    final r = _c.lastReport!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: const Key('sync-report'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              SyncStrings.lastResultTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (r.isNoOp)
              const Text(SyncStrings.noChanges)
            else ...[
              _sideTable(SyncStrings.changesHere, r.phone),
              _sideTable(SyncStrings.changesOther, r.watch),
              if (r.conflictsResolved > 0)
                Text(SyncStrings.conflicts(r.conflictsResolved)),
              if (r.orphansMovedToRoot > 0)
                Text(SyncStrings.orphans(r.orphansMovedToRoot)),
            ],
            const SizedBox(height: 4),
            Text(
              '${SyncStrings.sizeLine(r.bytesSent, r.bytesReceived)} in '
              '${SyncStrings.duration(r.duration)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideTable(String title, SyncSideReport side) {
    final rows = [
      for (final k in SyncEntityKind.values)
        if (!side.of(k).isEmpty)
          Text(
            '${SyncStrings.kindLabel(k)}: ${SyncStrings.counts(side.of(k).added, side.of(k).updated, side.of(k).deleted)}',
          ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (rows.isEmpty) const Text(SyncStrings.nothing) else ...rows,
        ],
      ),
    );
  }

  Widget _checkCard(BuildContext context) {
    final theme = Theme.of(context);
    final r = _c.checkResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(SyncStrings.checkTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(SyncStrings.checkHowTo, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('check-run'),
              onPressed: _c.canRunCheck ? _c.runCheck : null,
              child: Text(
                _c.checkRunning
                    ? SyncStrings.stageLabel(
                        _c.checkStage ?? SyncCheckStage.ping,
                      )
                    : SyncStrings.checkRun,
              ),
            ),
            if (r != null) ...[
              const SizedBox(height: 8),
              Text(
                r.passed ? SyncStrings.checkPass : SyncStrings.checkFail,
                key: const Key('check-verdict'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: r.passed ? Colors.green : theme.colorScheme.error,
                ),
              ),
              _checkRow(
                SyncStrings.checkPing,
                r.pingOk,
                SyncStrings.pingLine(r),
                'check-ping',
              ),
              _checkRow(
                SyncStrings.checkSend,
                r.send.ok,
                SyncStrings.transferLine(r.send),
                'check-send',
              ),
              _checkRow(
                SyncStrings.checkReceive,
                r.receive.ok,
                SyncStrings.transferLine(r.receive),
                'check-receive',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _checkRow(String label, bool ok, String detail, String key) =>
      ListTile(
        key: Key(key),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        title: Text(label),
        subtitle: Text(detail),
      );
}
