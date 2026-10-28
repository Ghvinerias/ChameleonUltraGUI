import 'dart:async';

import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/wear/features/read/strings.dart';
import 'package:chameleonultragui/wear/features/shared/slot_picker.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/progress_ring.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Slot names and card names stay within what the Chameleon stores.
const _maxNameLength = 32;

/// Opens the "Save to watch" page for [card]. Resolves true when saved.
Future<bool> saveCardToWatch(BuildContext context, CardSave card) async {
  final saved = await Navigator.of(context)
      .push<bool>(MaterialPageRoute(builder: (_) => SaveCardPage(card: card)));
  return saved ?? false;
}

/// Pick a slot, confirm if it is in use, then write [card] into it.
Future<void> writeCardToSlot(BuildContext context, CardSave card) async {
  final navigator = Navigator.of(context);
  final services = WearServicesScope.of(context);
  final slot = await pickSlot(
    context,
    title: ReadStrings.slotPickerTitle,
    confirmLabel: ReadStrings.slotPickerConfirm,
  );
  if (slot == null || !context.mounted) return;

  var inUse = true;
  try {
    final slots = await services.slotService?.getSlots();
    if (slots != null && slot < slots.length) {
      final s = slots[slot];
      final type = card.tag.value >= 1000 ? s.hfType : s.lfType;
      inUse = type != TagType.unknown;
    }
  } catch (_) {
    // Could not tell: ask to be safe.
  }
  if (!context.mounted) return;
  if (inUse) {
    final ok = await ConfirmDialog.show(
      context,
      title: ReadStrings.overwriteTitle,
      message: 'Slot ${slot + 1} will be replaced.',
      confirmLabel: ReadStrings.overwrite,
      cancelLabel: ReadStrings.cancel,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
  }
  await navigator.push<void>(
    MaterialPageRoute(
      builder: (_) => WriteToSlotPage(card: card, slot: slot),
    ),
  );
}

/// Editable name + Save. Writes through the watch [CardStore].
class SaveCardPage extends StatefulWidget {
  const SaveCardPage({super.key, required this.card});

  final CardSave card;

  @override
  State<SaveCardPage> createState() => _SaveCardPageState();
}

class _SaveCardPageState extends State<SaveCardPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.card.name,
  );
  bool _saving = false;
  bool _saved = false;
  bool _failed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = WearServicesScope.of(context).cardStore;
    final name = _name.text.trim();
    if (name.isNotEmpty) widget.card.name = name;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await store.saveCard(widget.card);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_saved) {
      return RoundScaffold(
        title: ReadStrings.saved,
        children: [
          Icon(Icons.check_circle, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            ReadStrings.savedBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          WearButton(
            label: ReadStrings.done,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    }
    return RoundScaffold(
      title: ReadStrings.saveTitle,
      children: [
        TextField(
          controller: _name,
          maxLength: _maxNameLength,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: ReadStrings.nameLabel,
            counterText: '',
            isDense: true,
          ),
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              ReadStrings.saveFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 6),
        WearButton(label: ReadStrings.save, onPressed: _saving ? null : _save),
      ],
    );
  }
}

/// Uploads [card] into [slot] with a progress ring and a result.
class WriteToSlotPage extends StatefulWidget {
  const WriteToSlotPage({super.key, required this.card, required this.slot});

  final CardSave card;
  final int slot;

  @override
  State<WriteToSlotPage> createState() => _WriteToSlotPageState();
}

class _WriteToSlotPageState extends State<WriteToSlotPage> {
  SlotUpload? _upload;
  StreamSubscription<SlotUploadEvent>? _sub;
  int _percent = 0;
  SlotUploadEvent? _result;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _run();
    }
  }

  void _run() {
    final service = WearServicesScope.of(context).slotService;
    setState(() {
      _percent = 0;
      _result = null;
    });
    if (service == null) {
      setState(
        () => _result = const SlotUploadFailed(SlotErrorCode.notConnected),
      );
      return;
    }
    try {
      final upload = service.uploadCard(
        widget.card,
        widget.slot,
        emptyNameFallback: ReadStrings.noNameFallback,
      );
      _upload = upload;
      _sub?.cancel();
      _sub = upload.events.listen((e) {
        if (!mounted) return;
        setState(() {
          switch (e) {
            case SlotUploadProgress():
              _percent = e.percent;
            case SlotUploadDone() || SlotUploadFailed():
              _result = e;
            case SlotUploadStarted():
              break;
          }
        });
      });
    } catch (_) {
      setState(() => _result = const SlotUploadFailed(SlotErrorCode.unknown));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    final upload = _upload;
    if (upload != null && _result == null) {
      unawaited(upload.cancel().catchError((_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    if (result == null) {
      return PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) unawaited(_upload?.cancel());
        },
        child: RoundScaffold(
          title: ReadStrings.writeTitle,
          children: [
            Center(
              child: ProgressRing(
                value: _percent / 100,
                size: 104,
                child: Text('$_percent%', style: theme.textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${ReadStrings.writing} ${widget.slot + 1}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            WearButton(
              label: ReadStrings.cancel,
              style: WearButtonStyle.tonal,
              onPressed: () => unawaited(_upload?.cancel()),
            ),
          ],
        ),
      );
    }
    final failed = result is SlotUploadFailed;
    return RoundScaffold(
      title: failed ? ReadStrings.writeFailed : ReadStrings.writeDone,
      children: [
        Icon(
          failed ? Icons.error_outline : Icons.check_circle,
          size: 48,
          color: failed ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          failed
              ? ReadStrings.slotFailure(result.code)
              : 'Slot ${widget.slot + 1} is ready.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        if (failed) WearButton(label: ReadStrings.retry, onPressed: _run),
        WearButton(
          label: failed ? ReadStrings.back : ReadStrings.done,
          style: failed ? WearButtonStyle.tonal : WearButtonStyle.filled,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
