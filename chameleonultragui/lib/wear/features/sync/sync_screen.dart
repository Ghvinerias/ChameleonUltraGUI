import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_engine.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/ui/strings.dart';
import 'package:chameleonultragui/sync/ui/sync_check.dart';
import 'package:chameleonultragui/sync/ui/sync_controller.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:chameleonultragui/wear/features/sync/strings.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/progress_ring.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Watch Sync screen. The protocol is phone-initiated (`SyncEngine.startSync`
/// is phone-only), so the watch answers: it shows link status, live progress of
/// a sync the phone started, the last result, and the link check.
class SyncScreen extends StatefulWidget {
  const SyncScreen({
    super.key,
    this.linkFactory = openWearSyncLink,
    this.options = const SyncOptions(),
    this.checkPayloadBytes = 1024 * 1024,
    this.checkTransferTimeout = const Duration(seconds: 30),
  });

  final SyncLinkFactory linkFactory;
  final SyncOptions options;
  final int checkPayloadBytes;
  final Duration checkTransferTimeout;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncUiController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final services = WearServicesScope.of(context);
    _c = SyncUiController(
      role: SyncRole.watch,
      linkFactory: widget.linkFactory,
      cards: services.cardStore,
      dictionaries: services.dictionaryStore,
      options: widget.options,
      checkPayloadBytes: widget.checkPayloadBytes,
      checkTransferTimeout: widget.checkTransferTimeout,
    )..start();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => RoundScaffold(
        title: WatchSyncStrings.title,
        children: [
          Center(child: _status(c)),
          const SizedBox(height: 8),
          ..._body(context, c),
        ],
      ),
    );
  }

  Widget _status(SyncUiController c) => switch (c.availability) {
    SyncAvailability.starting => const StatusPill(
      key: Key('sync-status'),
      label: SyncStrings.peerStarting,
    ),
    SyncAvailability.unsupported => StatusPill(
      key: const Key('sync-status'),
      label: SyncStrings.unsupportedTitle(c.unsupported!),
      kind: StatusKind.error,
      icon: Icons.sync_disabled,
    ),
    SyncAvailability.peerUnavailable => const StatusPill(
      key: Key('sync-status'),
      label: SyncStrings.peerUnavailable,
      kind: StatusKind.warning,
      icon: Icons.phonelink_off,
    ),
    SyncAvailability.peerAvailable => const StatusPill(
      key: Key('sync-status'),
      label: WatchSyncStrings.phoneConnected,
      kind: StatusKind.ok,
      icon: Icons.phone_android,
    ),
  };

  List<Widget> _body(BuildContext context, SyncUiController c) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    if (c.availability == SyncAvailability.unsupported) {
      return [
        Text(
          SyncStrings.unsupportedBody(c.unsupported!),
          textAlign: TextAlign.center,
          style: small,
        ),
      ];
    }
    if (c.availability == SyncAvailability.starting) return const [];
    return [
      if (c.running) ...[
        ..._running(context, c),
      ] else ...[
        ..._result(context, c),
        ..._idle(context, c),
      ],
      const SizedBox(height: 8),
      ..._library(context, c),
      const SizedBox(height: 8),
      ..._check(context, c),
    ];
  }

  List<Widget> _running(BuildContext context, SyncUiController c) {
    final theme = Theme.of(context);
    final p = c.progress;
    return [
      Center(
        child: ProgressRing(
          key: const Key('sync-progress'),
          value: p,
          size: 96,
          strokeWidth: 8,
          child: Text(
            p == null ? '...' : '${(p * 100).round()}%',
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        SyncStrings.phaseLabel(c.phase ?? SyncPhase.connecting),
        key: const Key('sync-phase'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall,
      ),
      Text(
        '${SyncStrings.bytes(c.bytesTransferred)} / '
        '${SyncStrings.bytes(c.bytesTotal)}',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
      WearButton(
        key: const Key('sync-cancel'),
        label: SyncStrings.cancel,
        style: WearButtonStyle.tonal,
        onPressed: c.cancel,
      ),
    ];
  }

  List<Widget> _idle(BuildContext context, SyncUiController c) {
    final theme = Theme.of(context);
    final waiting = c.availability == SyncAvailability.peerAvailable;
    return [
      Text(
        waiting
            ? WatchSyncStrings.waitingForPhone
            : WatchSyncStrings.peerUnavailableHint,
        key: const Key('sync-waiting'),
        textAlign: TextAlign.center,
        style: waiting ? theme.textTheme.titleSmall : theme.textTheme.bodySmall,
      ),
      if (waiting) ...[
        const SizedBox(height: 4),
        Text(
          WatchSyncStrings.howTo,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 4),
      Text(
        WatchSyncStrings.mirrorNote,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: WearColors.muted),
      ),
    ];
  }

  List<Widget> _library(BuildContext context, SyncUiController c) => [
    for (final k in SyncEntityKind.values)
      CompactListTile(
        key: Key('sync-lib-${k.name}'),
        title: SyncStrings.kindLabel(k),
        trailing: Text('${c.libraryCounts[k] ?? 0}'),
      ),
  ];

  List<Widget> _result(BuildContext context, SyncUiController c) {
    final theme = Theme.of(context);
    final err = c.lastError;
    if (err != null) {
      return [
        const SizedBox(height: 8),
        const Center(
          child: StatusPill(
            label: SyncStrings.lastFailureTitle,
            kind: StatusKind.error,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          SyncStrings.errorMessage(err),
          key: const Key('sync-error'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ];
    }
    final r = c.lastReport;
    if (r == null) return const [];
    final side = r.watch;
    return [
      const SizedBox(height: 8),
      const Center(
        child: StatusPill(
          label: SyncStrings.lastResultTitle,
          kind: StatusKind.ok,
          icon: Icons.check,
        ),
      ),
      const SizedBox(height: 4),
      Column(
        key: const Key('sync-report'),
        children: [
          if (r.isNoOp)
            Text(
              SyncStrings.noChanges,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            )
          else
            for (final k in SyncEntityKind.values)
              if (!side.of(k).isEmpty)
                CompactListTile(
                  title: SyncStrings.kindLabel(k),
                  subtitle: SyncStrings.counts(
                    side.of(k).added,
                    side.of(k).updated,
                    side.of(k).deleted,
                  ),
                ),
          if (r.conflictsResolved > 0)
            Text(
              SyncStrings.conflicts(r.conflictsResolved),
              style: theme.textTheme.bodySmall,
            ),
          if (r.orphansMovedToRoot > 0)
            Text(
              SyncStrings.orphans(r.orphansMovedToRoot),
              style: theme.textTheme.bodySmall,
            ),
          Text(
            '${SyncStrings.sizeLine(r.bytesSent, r.bytesReceived)}, '
            '${SyncStrings.duration(r.duration)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    ];
  }

  List<Widget> _check(BuildContext context, SyncUiController c) {
    final theme = Theme.of(context);
    final r = c.checkResult;
    return [
      Text(
        SyncStrings.checkTitle,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall,
      ),
      Text(
        WatchSyncStrings.checkHowTo,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
      WearButton(
        key: const Key('check-run'),
        label: c.checkRunning
            ? SyncStrings.stageLabel(c.checkStage ?? SyncCheckStage.ping)
            : SyncStrings.checkRun,
        style: WearButtonStyle.tonal,
        onPressed: c.canRunCheck ? c.runCheck : null,
      ),
      if (r != null) ...[
        Center(
          child: StatusPill(
            key: const Key('check-verdict'),
            label: r.passed ? SyncStrings.checkPass : SyncStrings.checkFail,
            kind: r.passed ? StatusKind.ok : StatusKind.error,
          ),
        ),
        _checkTile(
          'check-ping',
          SyncStrings.checkPing,
          r.pingOk,
          SyncStrings.pingLine(r),
        ),
        _checkTile(
          'check-send',
          SyncStrings.checkSend,
          r.send.ok,
          SyncStrings.transferLine(r.send),
        ),
        _checkTile(
          'check-receive',
          SyncStrings.checkReceive,
          r.receive.ok,
          SyncStrings.transferLine(r.receive),
        ),
      ],
    ];
  }

  Widget _checkTile(String key, String title, bool ok, String detail) =>
      CompactListTile(
        key: Key(key),
        title: title,
        subtitle: detail,
        leading: Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? WearColors.ok : WearColors.error,
        ),
      );
}
