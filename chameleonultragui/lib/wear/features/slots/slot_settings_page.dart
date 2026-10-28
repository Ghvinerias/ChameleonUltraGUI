import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/wear/features/slots/strings.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:flutter/material.dart';

/// Emulation options of one slot's HF tag (Mifare Classic and Ultralight/
/// NTAG), ported from the phone's slot edit dialog: toggles and short
/// pickers only. Values are read once when the page opens; every change is
/// written and then persisted with `saveSlotData` (as the phone does on Save).
///
/// The device applies these commands to the ACTIVE slot, so the page activates
/// the slot first (the phone does the same).
class SlotSettingsPage extends StatefulWidget {
  const SlotSettingsPage({
    super.key,
    required this.device,
    required this.slot,
    required this.hfType,
    required this.isActive,
    this.onActivated,
  });

  final ChameleonCommunicator device;
  final int slot;
  final TagType hfType;
  final bool isActive;
  final VoidCallback? onActivated;

  @override
  State<SlotSettingsPage> createState() => _SlotSettingsPageState();
}

class _SlotSettingsPageState extends State<SlotSettingsPage> {
  EmulatorSettings? _settings;
  Mf1PrngType? _prng;
  CardData? _anticoll;
  Object? _error;
  bool _busy = false;
  StatusPill? _status;

  bool get _classic => isMifareClassic(widget.hfType);

  ChameleonCommunicator get _d => widget.device;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _settings = null;
    });
    try {
      if (!widget.isActive) {
        await _d.activateSlot(widget.slot);
        widget.onActivated?.call();
      }
      if (_classic) {
        final s = await _d.getMf1EmulatorSettings();
        final p = await _d.getMf1PrngType();
        CardData? ac;
        try {
          ac = await _d.mf1GetAntiCollData();
        } catch (_) {
          // Read-only extra; the toggles still work without it.
        }
        if (!mounted) return;
        setState(() {
          _settings = s;
          _prng = p;
          _anticoll = ac;
        });
      } else {
        final s = await _d.mf0NtagGetEmulatorConfig();
        if (!mounted) return;
        setState(() => _settings = s);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// Applies [apply] to the UI at once, writes + saves, and on failure runs
  /// [revert] and shows the error.
  Future<void> _change({
    required Future<void> Function() write,
    required VoidCallback apply,
    required VoidCallback revert,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      apply();
    });
    try {
      await write();
      await _d.saveSlotData();
      if (!mounted) return;
      setState(() {
        _status = const StatusPill(
          label: SlotStrings.saved,
          kind: StatusKind.ok,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        revert();
        _status = StatusPill(
          label: SlotStrings.failed(e),
          kind: StatusKind.error,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _toggle(
    String label,
    bool value,
    Future<void> Function(bool) write,
    void Function(bool) set,
  ) => CompactListTile(
    title: label,
    trailing: Switch(
      value: value,
      onChanged: _busy ? null : (v) => _toggleTo(v, value, write, set),
    ),
    onTap: _busy ? null : () => _toggleTo(!value, value, write, set),
  );

  Future<void> _toggleTo(
    bool next,
    bool previous,
    Future<void> Function(bool) write,
    void Function(bool) set,
  ) => _change(
    write: () => write(next),
    apply: () => set(next),
    revert: () => set(previous),
  );

  Future<T?> _pick<T>(
    String title,
    List<T> options,
    String Function(T) label,
    T current,
  ) => Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (context) => RoundScaffold(
        title: title,
        children: [
          for (final o in options)
            CompactListTile(
              title: label(o),
              trailing: o == current ? const Icon(Icons.check, size: 18) : null,
              onTap: () => Navigator.of(context).pop(o),
            ),
        ],
      ),
    ),
  );

  Widget _writeModeRow(Future<void> Function(MifareWriteMode) write) {
    final s = _settings!;
    return CompactListTile(
      title: SlotStrings.writeMode,
      subtitle: SlotStrings.writeModeLabel(s.writeMode),
      onTap: _busy
          ? null
          : () async {
              final prev = s.writeMode;
              final next = await _pick(
                SlotStrings.writeMode,
                MifareWriteMode.values,
                SlotStrings.writeModeLabel,
                prev,
              );
              if (next == null || next == prev || !mounted) return;
              await _change(
                write: () => write(next),
                apply: () => s.writeMode = next,
                revert: () => s.writeMode = prev,
              );
            },
    );
  }

  Widget _prngRow() {
    final prev = _prng!;
    return CompactListTile(
      title: SlotStrings.prng,
      subtitle: SlotStrings.prngLabel(prev),
      onTap: _busy
          ? null
          : () async {
              final next = await _pick(
                SlotStrings.prng,
                Mf1PrngType.values,
                SlotStrings.prngLabel,
                prev,
              );
              if (next == null || next == prev || !mounted) return;
              await _change(
                write: () => _d.setMf1PrngType(next),
                apply: () => _prng = next,
                revert: () => _prng = prev,
              );
            },
    );
  }

  List<Widget> _classicRows(EmulatorSettings s) => [
    _toggle(
      SlotStrings.gen1a,
      s.isGen1a,
      _d.setMf1Gen1aMode,
      (v) => s.isGen1a = v,
    ),
    _toggle(SlotStrings.gen2, s.isGen2, _d.setMf1Gen2Mode, (v) => s.isGen2 = v),
    _toggle(
      SlotStrings.block0Anticoll,
      s.isAntiColl,
      _d.setMf1UseFirstBlockColl,
      (v) => s.isAntiColl = v,
    ),
    _toggle(
      SlotStrings.detection,
      s.isDetectionEnabled,
      _d.setMf1DetectionStatus,
      (v) => s.isDetectionEnabled = v,
    ),
    _prngRow(),
    _writeModeRow(_d.setMf1WriteMode),
    ..._readOnlyRows(),
  ];

  List<Widget> _ultralightRows(EmulatorSettings s) => [
    _toggle(
      SlotStrings.uidMagic,
      s.isGen2,
      _d.mf0SetMagicMode,
      (v) => s.isGen2 = v,
    ),
    _toggle(
      SlotStrings.detection,
      s.isDetectionEnabled,
      _d.mf0NtagSetDetectionEnable,
      (v) => s.isDetectionEnabled = v,
    ),
    _writeModeRow(_d.mf0NtagSetWriteMode),
  ];

  /// UID/ATQA/SAK need free-form hex input: shown, not editable.
  List<Widget> _readOnlyRows() {
    final ac = _anticoll;
    return [
      if (ac != null) ...[
        CompactListTile(
          title: SlotStrings.readOnlyUid,
          subtitle: bytesToHexSpace(ac.uid),
        ),
        CompactListTile(
          title: '${SlotStrings.readOnlyAtqa} / ${SlotStrings.readOnlySak}',
          subtitle:
              '${bytesToHexSpace(ac.atqa)} / ${ac.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        ),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          SlotStrings.phoneOnly,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final title = '${SlotStrings.slot(widget.slot)} ${SlotStrings.settings}';
    final s = _settings;
    if (_error != null) {
      return RoundScaffold(
        title: title,
        children: [
          Text(
            SlotStrings.settingsLoadFailed,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            SlotStrings.failed(_error!),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          CompactListTile(title: SlotStrings.retry, onTap: _load),
        ],
      );
    }
    if (s == null) {
      return const RoundScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return RoundScaffold(
      title: title,
      children: [
        if (_status != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _status!,
            ),
          ),
        ..._classic ? _classicRows(s) : _ultralightRows(s),
      ],
    );
  }
}
