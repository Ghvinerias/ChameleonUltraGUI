import 'dart:async';

import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/wear/features/saved_cards/strings.dart';
import 'package:chameleonultragui/wear/features/shared/slot_picker.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/progress_ring.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

enum _Phase { starting, uploading, done, failed }

/// Pick a slot, confirm overwriting, write the card, show the result.
///
/// Must sit inside a `WearConnectionGate`. Leaving the page (back swipe or
/// disconnect) cancels a running upload.
class LoadToSlotPage extends StatefulWidget {
  const LoadToSlotPage({super.key, required this.card});

  final CardSave card;

  @override
  State<LoadToSlotPage> createState() => _LoadToSlotPageState();
}

class _LoadToSlotPageState extends State<LoadToSlotPage> {
  _Phase _phase = _Phase.starting;
  int _slot = 0;
  int _percent = 0;
  String _message = SavedCardsStrings.checkingSlot;
  SlotUpload? _upload;
  StreamSubscription<SlotUploadEvent>? _sub;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    final up = _upload;
    if (up != null && !_finished) up.cancel();
    super.dispose();
  }

  static bool _used(SlotInfo s) =>
      s.hfType != TagType.unknown || s.lfType != TagType.unknown;

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _message = message;
    });
  }

  Future<void> _run() async {
    final service = WearServicesScope.of(context).slotService;
    if (service == null) {
      _fail(SavedCardsStrings.uploadError(SlotErrorCode.notConnected));
      return;
    }
    setState(() {
      _phase = _Phase.starting;
      _message = SavedCardsStrings.checkingSlot;
    });

    int slot;
    while (true) {
      final picked = await pickSlot(
        context,
        title: SavedCardsStrings.pickSlotTitle,
        confirmLabel: SavedCardsStrings.pickSlotConfirm,
      );
      if (!mounted) return;
      if (picked == null) {
        Navigator.of(context).pop();
        return;
      }
      SlotInfo info;
      try {
        info = (await service.getSlots())[picked];
      } catch (_) {
        _fail(SavedCardsStrings.uploadError(SlotErrorCode.communication));
        return;
      }
      if (!mounted) return;
      if (_used(info)) {
        final name = info.hfName.isNotEmpty ? info.hfName : info.lfName;
        final ok = await ConfirmDialog.show(
          context,
          title: SavedCardsStrings.overwriteTitle(picked),
          message: SavedCardsStrings.overwriteBody(
            name.isEmpty ? SavedCardsStrings.slotInUse : '"$name"',
          ),
          confirmLabel: SavedCardsStrings.overwrite,
          cancelLabel: SavedCardsStrings.cancel,
          destructive: true,
        );
        if (!mounted) return;
        if (!ok) continue;
      }
      slot = picked;
      break;
    }

    setState(() {
      _slot = slot;
      _percent = 0;
      _phase = _Phase.uploading;
      _finished = false;
    });
    final upload = service.uploadCard(
      widget.card,
      slot,
      emptyNameFallback: SavedCardsStrings.unnamed,
    );
    _upload = upload;
    _sub = upload.events.listen((e) {
      if (e is SlotUploadProgress && mounted) {
        setState(() => _percent = e.percent.clamp(0, 100));
      }
    });
    final end = await upload.terminal;
    _finished = true;
    unawaited(_sub?.cancel());
    if (!mounted) return;
    switch (end) {
      case SlotUploadDone():
        setState(() => _phase = _Phase.done);
      case SlotUploadFailed(:final code):
        _fail(SavedCardsStrings.uploadError(code));
      default:
        _fail(SavedCardsStrings.uploadError(SlotErrorCode.unknown));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (_phase) {
      case _Phase.starting:
        return RoundScaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 10),
                Text(_message, textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      case _Phase.uploading:
        return RoundScaffold(
          children: [
            Center(
              child: ProgressRing(
                value: _percent / 100,
                size: 88,
                strokeWidth: 9,
                child: Text('$_percent%', style: theme.textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              SavedCardsStrings.uploading(_slot),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            WearButton(
              label: SavedCardsStrings.cancelUpload,
              style: WearButtonStyle.tonal,
              onPressed: () => _upload?.cancel(),
            ),
          ],
        );
      case _Phase.done:
        return RoundScaffold(
          children: [
            const Icon(Icons.check_circle, size: 56, color: WearColors.ok),
            const SizedBox(height: 6),
            Text(
              SavedCardsStrings.uploaded(_slot),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            WearButton(
              label: SavedCardsStrings.done,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      case _Phase.failed:
        return RoundScaffold(
          children: [
            const Icon(Icons.error_outline, size: 48, color: WearColors.error),
            const SizedBox(height: 6),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            WearButton(label: SavedCardsStrings.retry, onPressed: _run),
            WearButton(
              label: SavedCardsStrings.close,
              style: WearButtonStyle.tonal,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
    }
  }
}
