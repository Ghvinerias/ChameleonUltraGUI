import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/wear/features/slots/slot_rename_page.dart';
import 'package:chameleonultragui/wear/features/slots/slot_routes.dart';
import 'package:chameleonultragui/wear/features/slots/slot_settings_page.dart';
import 'package:chameleonultragui/wear/features/slots/strings.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// One slot: names, types, enabled flags and the actions on them. All data
/// comes from the overview (no extra device reads).
class SlotDetailPage extends StatefulWidget {
  const SlotDetailPage({
    super.key,
    required this.device,
    required this.slot,
    required this.isActive,
  });

  final ChameleonCommunicator device;
  final SlotInfo slot;
  final bool isActive;

  @override
  State<SlotDetailPage> createState() => _SlotDetailPageState();
}

class _SlotDetailPageState extends State<SlotDetailPage> {
  late bool _active = widget.isActive;
  late TagType _hfType = widget.slot.hfType;
  late TagType _lfType = widget.slot.lfType;
  late bool _hfEnabled = widget.slot.hfEnabled;
  late bool _lfEnabled = widget.slot.lfEnabled;
  late String _hfName = widget.slot.hfName;
  late String _lfName = widget.slot.lfName;
  bool _busy = false;
  StatusPill? _status;

  int get _index => widget.slot.index;

  SlotService get _service => WearServicesScope.of(context).slotService!;

  void _ok(String text) =>
      _status = StatusPill(label: text, kind: StatusKind.ok);
  void _fail(Object e) => _status = StatusPill(
    label: SlotStrings.failed(e),
    kind: StatusKind.error,
  );

  /// Runs [action] with the busy lock; [onOk] updates local state afterwards.
  Future<void> _run(
    String okText,
    Future<void> Function() action,
    VoidCallback onOk,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() {
        onOk();
        _ok(okText);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _fail(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate() => _run(
    SlotStrings.activated,
    () => _service.activateSlot(_index),
    () => _active = true,
  );

  Future<void> _setEnabled(TagFrequency f, bool value) => _run(
    SlotStrings.saved,
    () => _service.setSlotEnabled(_index, f, value),
    () => f == TagFrequency.hf ? _hfEnabled = value : _lfEnabled = value,
  );

  Future<void> _rename(TagFrequency f) async {
    final hf = f == TagFrequency.hf;
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SlotRenamePage(
          title:
              '${SlotStrings.rename} ${hf ? SlotStrings.hf : SlotStrings.lf}',
          initial: hf ? _hfName : _lfName,
        ),
      ),
    );
    if (name == null || !mounted) return;
    await _run(
      SlotStrings.saved,
      () => _service.renameSlot(_index, f, name),
      () => hf ? _hfName = name : _lfName = name,
    );
  }

  Future<void> _clear(TagFrequency f) async {
    final hf = f == TagFrequency.hf;
    final label = hf ? SlotStrings.hf : SlotStrings.lf;
    final ok = await ConfirmDialog.show(
      context,
      title: SlotStrings.clearTitle(label),
      message: SlotStrings.clearMessage,
      confirmLabel: SlotStrings.clear,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      SlotStrings.cleared,
      () async {
        // Same sequence as the phone's slot settings dialog.
        await widget.device.deleteSlotInfo(_index, f);
        await widget.device.setSlotTagName(_index, SlotStrings.empty, f);
        await widget.device.saveSlotData();
      },
      () {
        if (hf) {
          _hfType = TagType.unknown;
          _hfName = SlotStrings.empty;
        } else {
          _lfType = TagType.unknown;
          _lfName = SlotStrings.empty;
        }
      },
    );
  }

  List<Widget> _half(TagFrequency f) {
    final hf = f == TagFrequency.hf;
    final label = hf ? SlotStrings.hf : SlotStrings.lf;
    final type = hf ? _hfType : _lfType;
    final name = hf ? _hfName : _lfName;
    final enabled = hf ? _hfEnabled : _lfEnabled;
    if (type == TagType.unknown) {
      return [CompactListTile(title: label, subtitle: SlotStrings.empty)];
    }
    return [
      CompactListTile(
        title: '$label · ${SlotStrings.tagLabel(type)}',
        subtitle: name.isEmpty ? SlotStrings.noName : name,
        trailing: const Icon(Icons.edit, size: 18),
        onTap: _busy ? null : () => _rename(f),
      ),
      CompactListTile(
        title: '$label ${SlotStrings.enabled}',
        trailing: Switch(
          value: enabled,
          onChanged: _busy ? null : (v) => _setEnabled(f, v),
        ),
        onTap: _busy ? null : () => _setEnabled(f, !enabled),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasSettings = isMifareClassic(_hfType) || isMifareUltralight(_hfType);
    return RoundScaffold(
      title: SlotStrings.slot(_index),
      children: [
        if (_status != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _status!,
            ),
          ),
        if (_active)
          const Center(
            child: StatusPill(
              label: SlotStrings.active,
              kind: StatusKind.info,
              icon: Icons.check,
            ),
          )
        else
          WearButton(
            label: SlotStrings.activate,
            onPressed: _busy ? null : _activate,
          ),
        ..._half(TagFrequency.hf),
        ..._half(TagFrequency.lf),
        if (hasSettings)
          WearButton(
            label: SlotStrings.settings,
            style: WearButtonStyle.tonal,
            icon: Icons.tune,
            onPressed: _busy
                ? null
                : () => pushDevicePage<void>(
                    context,
                    (context, device) => SlotSettingsPage(
                      device: device,
                      slot: _index,
                      hfType: _hfType,
                      isActive: _active,
                      onActivated: () {
                        if (mounted) setState(() => _active = true);
                      },
                    ),
                  ),
          ),
        if (_hfType != TagType.unknown)
          WearButton(
            label: '${SlotStrings.clear} ${SlotStrings.hf}',
            style: WearButtonStyle.destructive,
            onPressed: _busy ? null : () => _clear(TagFrequency.hf),
          ),
        if (_lfType != TagType.unknown)
          WearButton(
            label: '${SlotStrings.clear} ${SlotStrings.lf}',
            style: WearButtonStyle.destructive,
            onPressed: _busy ? null : () => _clear(TagFrequency.lf),
          ),
      ],
    );
  }
}
