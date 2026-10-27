import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Opens the slot picker and resolves to the chosen slot (0..7), or null if
/// the user backs out. Needs a connected device (wrap the caller in a
/// `WearConnectionGate`).
Future<int?> pickSlot(
  BuildContext context, {
  String title = 'Choose slot',
  String confirmLabel = 'Use slot',
}) => Navigator.of(context).push<int>(
  MaterialPageRoute(
    builder: (_) => SlotPickerPage(title: title, confirmLabel: confirmLabel),
  ),
);

/// Ring of the 8 emulator slots; tap a slot, then confirm. Shared by the
/// Read, Saved cards and Slots features.
class SlotPickerPage extends StatefulWidget {
  const SlotPickerPage({
    super.key,
    this.title = 'Choose slot',
    this.confirmLabel = 'Use slot',
  });

  final String title;
  final String confirmLabel;

  @override
  State<SlotPickerPage> createState() => _SlotPickerPageState();
}

class _SlotPickerPageState extends State<SlotPickerPage> {
  List<SlotInfo>? _slots;
  Object? _error;
  int? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_slots == null && _error == null) _load();
  }

  Future<void> _load() async {
    final service = WearServicesScope.of(context).slotService;
    if (service == null) {
      setState(() => _error = 'not connected');
      return;
    }
    try {
      final slots = await service.getSlots();
      if (mounted) setState(() => _slots = slots);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static bool _used(SlotInfo s) =>
      s.hfType != TagType.unknown || s.lfType != TagType.unknown;

  String _describe(SlotInfo s) {
    if (!_used(s)) return 'Empty';
    final name = s.hfName.isNotEmpty ? s.hfName : s.lfName;
    return name.isEmpty ? 'In use' : name;
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    if (_error != null) {
      return RoundScaffold(
        title: widget.title,
        children: [Center(child: Text('Could not read slots: $_error'))],
      );
    }
    if (slots == null) {
      return RoundScaffold(
        title: widget.title,
        children: const [Center(child: CircularProgressIndicator())],
      );
    }
    final states = [
      for (final s in slots) _used(s) ? SlotState.used : SlotState.empty,
    ];
    final selected = _selected;
    return RoundScaffold(
      title: widget.title,
      children: [
        Center(
          child: SlotRing(
            states: states,
            size: 104,
            strokeWidth: 12,
            onSlotTap: (i) => setState(() => _selected = i),
            child: Text(
              selected == null
                  ? 'Tap a slot'
                  : 'Slot ${selected + 1}\n${_describe(slots[selected])}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        const SizedBox(height: 8),
        WearButton(
          label: selected == null
              ? widget.confirmLabel
              : '${widget.confirmLabel} ${selected + 1}',
          onPressed: selected == null
              ? null
              : () => Navigator.of(context).pop(selected),
        ),
      ],
    );
  }
}
