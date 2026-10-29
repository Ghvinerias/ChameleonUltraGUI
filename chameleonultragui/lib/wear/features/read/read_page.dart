import 'dart:async';

import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/wear/features/read/card_conversion.dart';
import 'package:chameleonultragui/wear/features/read/key_map.dart';
import 'package:chameleonultragui/wear/features/read/read_controller.dart';
import 'package:chameleonultragui/wear/features/read/read_effects.dart';
import 'package:chameleonultragui/wear/features/read/save_pages.dart';
import 'package:chameleonultragui/wear/features/read/strings.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/edge_progress.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/scan_pulse.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// One read / scan run: animation while scanning, then the result card with
/// the Mifare Classic steps and the save / write actions. Leaving the page
/// cancels the running session.
class ReadPage extends StatefulWidget {
  const ReadPage({
    super.key,
    required this.mode,
    this.effects = const ReadEffects(),
    this.animate = true,
  });

  final ReadMode mode;
  final ReadEffects effects;

  /// False freezes the scan animation (tests that pump with `pumpAndSettle`).
  final bool animate;

  @override
  State<ReadPage> createState() => _ReadPageState();
}

class _ReadPageState extends State<ReadPage> {
  ReadController? _controller;
  final ScrollController _scroll = ScrollController();
  ReadStage? _lastStage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      _controller = ReadController(
        services: WearServicesScope.of(context),
        mode: widget.mode,
        effects: widget.effects,
      );
      _controller!.addListener(_onChanged);
      unawaited(_controller!.start());
    }
  }

  /// A new stage is a new screen: show it from the top.
  void _onChanged() {
    final stage = _controller!.stage;
    if (stage != _lastStage) {
      _lastStage = stage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _title(ReadMode m) => switch (m) {
    ReadMode.hf => ReadStrings.readHf,
    ReadMode.lf => ReadStrings.readLf,
    ReadMode.scanHf => ReadStrings.scanHfShort,
    ReadMode.scanLf => ReadStrings.scanLfShort,
  };

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    return PopScope(
      // Stop talking to the Chameleon the moment the page is popped, not when
      // the exit transition finishes.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(c.stop());
      },
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final scaffold = RoundScaffold(
            title: _title(widget.mode),
            controller: _scroll,
            children: _children(context, c),
          );
          final progress = _edgeProgress(c);
          if (progress == null) return scaffold;
          return Stack(
            fit: StackFit.expand,
            children: [
              scaffold,
              Positioned.fill(
                child: EdgeProgress(
                  value: progress.value,
                  animate: widget.animate,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Progress along the screen edge for the long-running stages; null when
  /// the stage has none. Inner value null = indeterminate.
  ({double? value})? _edgeProgress(ReadController c) {
    switch (c.stage) {
      case ReadStage.checkingKeys:
        final k = c.keyCheck;
        final total = k?.sectorsTotal ?? _sectors(c);
        return (value: total == 0 ? null : (k?.sectorsDone ?? 0) / total);
      case ReadStage.recovering:
        return (value: c.recovery?.progress);
      case ReadStage.dumping:
        return (value: c.dumpProgress?.fraction);
      default:
        return null;
    }
  }

  List<Widget> _children(BuildContext context, ReadController c) {
    switch (c.stage) {
      case ReadStage.preparing:
        return [
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          _Message(ReadStrings.preparing),
        ];
      case ReadStage.scanning:
      case ReadStage.identifying:
        return _scanning(c);
      case ReadStage.checkingKeys:
        return _checking(c);
      case ReadStage.recovering:
        return _recovering(c);
      case ReadStage.dumping:
        return _dumping(c);
      case ReadStage.result:
        return _result(context, c);
      case ReadStage.noCard:
        return [
          _Headline(ReadStrings.noCardTitle, icon: Icons.nfc, muted: true),
          _Message(ReadStrings.noCardBody),
          WearButton(label: ReadStrings.retry, onPressed: c.start),
        ];
      case ReadStage.stopped:
        return [
          _Headline(
            c.timedOut ? ReadStrings.timedOutTitle : ReadStrings.stoppedTitle,
            icon: Icons.stop_circle_outlined,
            muted: true,
          ),
          if (c.timedOut) _Message(ReadStrings.timedOutBody),
          WearButton(
            label: c.mode.isContinuous
                ? ReadStrings.scanAgain
                : ReadStrings.readAgain,
            onPressed: c.start,
          ),
        ];
      case ReadStage.failed:
        return _failed(c);
    }
  }

  // ---- progress states ---------------------------------------------------

  List<Widget> _scanning(ReadController c) {
    final found = c.stage == ReadStage.identifying;
    final card = c.hfCard;
    return [
      Center(
        child: ScanPulse(
          size: 104,
          animate: widget.animate,
          child: c.mode.isContinuous
              ? Text(
                  '${c.attempt}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : null,
        ),
      ),
      const SizedBox(height: 8),
      if (found) ...[
        _Headline(ReadStrings.cardFound, icon: Icons.check_circle),
        if (card != null) _Message(bytesToHexSpace(card.uid)),
        if (c.lfCard != null) _Message(c.lfCard!.toString()),
      ] else ...[
        _Message(ReadStrings.placeCard),
        if (c.mode.isContinuous)
          _Message(ReadStrings.attempt(c.attempt), muted: true),
      ],
      const SizedBox(height: 4),
      WearButton(
        label: c.mode.isContinuous ? ReadStrings.stop : ReadStrings.cancel,
        style: WearButtonStyle.tonal,
        onPressed: () => unawaited(c.stop()),
      ),
    ];
  }

  int _sectors(ReadController c) {
    final mfc = c.hf?.mifareClassic;
    if (mfc != null) {
      return mfClassicGetSectorCount(mfc.type, isEV1: mfc.isEV1);
    }
    return c.keyCheck?.sectorsTotal ?? 16;
  }

  List<Widget> _checking(ReadController c) {
    final k = c.keyCheck;
    final total = k?.sectorsTotal ?? _sectors(c);
    final done = k?.sectorsDone ?? 0;
    return [
      _BigStat('$done/$total', ReadStrings.checkingKeys),
      const SizedBox(height: 6),
      SectorKeyMap(states: k?.sectorStates ?? const [], sectors: total),
      const SizedBox(height: 8),
      WearButton(
        label: ReadStrings.cancel,
        style: WearButtonStyle.tonal,
        onPressed: () => unawaited(c.stop()),
      ),
    ];
  }

  List<Widget> _recovering(ReadController c) {
    final r = c.recovery;
    final sectors = _sectors(c);
    final states =
        c.hf?.mifareClassic?.sectorStates ?? c.keyCheck?.sectorStates;
    final detail = <String>[
      if (r != null && r.sector != null)
        'Sector ${r.sector}${r.keyType == null ? '' : (r.keyType == 0 ? ' key A' : ' key B')}',
      if (r != null && r.viaBackdoor) ReadStrings.viaBackdoor,
    ].join(' · ');
    return [
      _BigStat(
        r == null ? '…' : '${r.keysFound}',
        r == null ? ReadStrings.recovering : ReadStrings.attackName(r.attack),
      ),
      if (detail.isNotEmpty) _Message(detail, muted: true),
      if (states != null) ...[
        const SizedBox(height: 6),
        SectorKeyMap(states: states, sectors: sectors, showMissing: true),
      ],
      const SizedBox(height: 8),
      WearButton(
        label: ReadStrings.cancel,
        style: WearButtonStyle.tonal,
        onPressed: () => unawaited(c.stop()),
      ),
    ];
  }

  List<Widget> _dumping(ReadController c) {
    final d = c.dumpProgress;
    return [
      _BigStat(
        d == null ? '…' : '${(d.fraction * 100).round()}%',
        ReadStrings.dumping,
      ),
      if (d != null) _Message('${d.blocksDone}/${d.blocksTotal}', muted: true),
      const SizedBox(height: 8),
      WearButton(
        label: ReadStrings.cancel,
        style: WearButtonStyle.tonal,
        onPressed: () => unawaited(c.stop()),
      ),
    ];
  }

  // ---- failure -----------------------------------------------------------

  List<Widget> _failed(ReadController c) {
    final code = c.error ?? ReadErrorCode.unknown;
    final (title, body) = ReadStrings.failure(code);
    final hardnested = code == ReadErrorCode.hardnestedUnavailable;
    final cardLost = code == ReadErrorCode.cardLost;
    final step = c.failedStep;
    final hasResult = c.hf != null || c.lf != null;
    return [
      _Headline(
        title,
        icon: hardnested ? Icons.smartphone : Icons.error_outline,
        warning: hardnested,
        error: !hardnested,
      ),
      _Message(body),
      const SizedBox(height: 4),
      if (!hardnested || step == null)
        WearButton(
          label: ReadStrings.retry,
          onPressed: step != null && c.hf?.mifareClassic != null
              ? () => unawaited(c.continueMifare(step))
              : c.start,
        ),
      if (hasResult && (hardnested || cardLost || step != null))
        WearButton(
          label: ReadStrings.back,
          style: WearButtonStyle.tonal,
          onPressed: c.backToResult,
        ),
    ];
  }

  // ---- result ------------------------------------------------------------

  List<Widget> _result(BuildContext context, ReadController c) {
    final hf = c.hf;
    final lf = c.lf;
    if (hf != null && hf.card != null) return _hfResult(context, c, hf);
    if (lf != null && lf.card != null) return _lfResult(context, c, lf);
    return [_Message(ReadStrings.noCardBody)];
  }

  List<Widget> _hfResult(
    BuildContext context,
    ReadController c,
    HfReadResult r,
  ) {
    final card = r.card!;
    final mfc = r.mifareClassic;
    final mfu = r.mifareUltralight;
    final save = cardSaveFromHf(r, name: defaultCardName(r.type, card.uid));
    return [
      Center(
        child: StatusPill(
          label: longTagName(r.type),
          kind: r.type.name == 'unknown' ? StatusKind.warning : StatusKind.ok,
        ),
      ),
      const SizedBox(height: 6),
      _InfoRow(ReadStrings.uid, bytesToHexSpace(card.uid)),
      _InfoRow(ReadStrings.atqa, bytesToHexSpace(card.atqa)),
      _InfoRow(
        ReadStrings.sak,
        card.sak.toRadixString(16).padLeft(2, '0').toUpperCase(),
      ),
      _InfoRow(
        ReadStrings.ats,
        card.ats.isEmpty ? ReadStrings.none : bytesToHexSpace(card.ats),
      ),
      if (mfc != null) ..._mfcSection(context, c, mfc),
      if (mfu != null) ..._mfuSection(mfu),
      const SizedBox(height: 4),
      if (mfc != null) ..._mfcSteps(c, mfc),
      if (save != null) ..._saveActions(context, save),
      WearButton(
        label: c.mode.isContinuous
            ? ReadStrings.scanAgain
            : ReadStrings.readAgain,
        style: WearButtonStyle.tonal,
        onPressed: c.start,
      ),
    ];
  }

  List<Widget> _mfcSection(
    BuildContext context,
    ReadController c,
    MifareClassicReadState mfc,
  ) {
    final sectors = mfClassicGetSectorCount(mfc.type, isEV1: mfc.isEV1);
    final found = SectorKeyMap.foundCount(mfc.sectorStates, sectors);
    final checked = mfc.completedDepth != MifareClassicDepth.identify;
    return [
      _InfoRow(
        ReadStrings.nt,
        '${ReadStrings.ntLevel(mfc.ntLevel)}${mfc.isEV1 ? ' · ${ReadStrings.ev1}' : ''}'
        '${mfc.hasBackdoor == true ? ' · ${ReadStrings.backdoor}' : ''}',
      ),
      if (checked) ...[
        _InfoRow(ReadStrings.keys, ReadStrings.keysFound(found, sectors * 2)),
        const SizedBox(height: 4),
        SectorKeyMap(
          states: mfc.sectorStates,
          sectors: sectors,
          showMissing: true,
        ),
      ],
    ];
  }

  List<Widget> _mfcSteps(ReadController c, MifareClassicReadState mfc) {
    final depth = mfc.completedDepth;
    return [
      if (depth == MifareClassicDepth.identify)
        WearButton(
          label: ReadStrings.checkKeys,
          icon: Icons.vpn_key_outlined,
          onPressed: () =>
              unawaited(c.continueMifare(MifareClassicDepth.checkKeys)),
        ),
      if (depth == MifareClassicDepth.checkKeys && !mfc.allKeysFound)
        WearButton(
          label: ReadStrings.recoverKeys,
          icon: Icons.lock_open,
          onPressed: () =>
              unawaited(c.continueMifare(MifareClassicDepth.recoverKeys)),
        ),
      if (depth == MifareClassicDepth.checkKeys ||
          depth == MifareClassicDepth.recoverKeys)
        WearButton(
          label: ReadStrings.dump,
          icon: Icons.download,
          onPressed: () => unawaited(c.continueMifare(MifareClassicDepth.dump)),
        ),
    ];
  }

  List<Widget> _mfuSection(MifareUltralightReadState mfu) => [
    if (mfu.version != null && mfu.version!.isNotEmpty)
      _InfoRow(ReadStrings.version, bytesToHexSpace(mfu.version!)),
    _InfoRow(
      ReadStrings.signature,
      mfu.signature != null && mfu.signature!.isNotEmpty
          ? ReadStrings.yes
          : ReadStrings.no,
    ),
    _Message(ReadStrings.infoOnly, muted: true),
  ];

  List<Widget> _saveActions(BuildContext context, CardSave save) => [
    WearButton(
      label: ReadStrings.saveToWatch,
      icon: Icons.save_alt,
      onPressed: () => unawaited(saveCardToWatch(context, save)),
    ),
    WearButton(
      label: ReadStrings.writeToSlot,
      icon: Icons.upload,
      onPressed: () => unawaited(writeCardToSlot(context, save)),
    ),
  ];

  List<Widget> _lfResult(
    BuildContext context,
    ReadController c,
    LfReadResult r,
  ) {
    final card = r.card!;
    final save = cardSaveFromLf(
      card,
      name: defaultCardName(card.type, card.uid),
    );
    return [
      Center(
        child: StatusPill(label: longTagName(card.type), kind: StatusKind.ok),
      ),
      const SizedBox(height: 6),
      _InfoRow(ReadStrings.id, card.toViewableString()),
      const SizedBox(height: 4),
      ..._saveActions(context, save),
      WearButton(
        label: c.mode.isContinuous
            ? ReadStrings.scanAgain
            : ReadStrings.readAgain,
        style: WearButtonStyle.tonal,
        onPressed: c.start,
      ),
    ];
  }
}

class _Headline extends StatelessWidget {
  const _Headline(
    this.text, {
    required this.icon,
    this.muted = false,
    this.warning = false,
    this.error = false,
  });

  final String text;
  final IconData icon;
  final bool muted;
  final bool warning;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = error
        ? WearColors.error
        : warning
        ? WearColors.warning
        : muted
        ? WearColors.muted
        : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: muted ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Large figure with a caption underneath: the centre of a progress stage
/// (the progress itself runs along the screen edge).
class _BigStat extends StatelessWidget {
  const _BigStat(this.value, this.caption);

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 30,
              height: 1.1,
            ),
          ),
        ),
        Text(
          caption,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
