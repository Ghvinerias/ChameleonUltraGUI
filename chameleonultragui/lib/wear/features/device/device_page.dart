import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/wear/features/device/ble_page.dart';
import 'package:chameleonultragui/wear/features/device/device_controller.dart';
import 'package:chameleonultragui/wear/features/device/settings_page.dart';
import 'package:chameleonultragui/wear/features/device/strings.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Device info, settings entry points, disconnect and forget.
class DevicePage extends StatelessWidget {
  const DevicePage({super.key});

  @override
  Widget build(BuildContext context) => WearConnectionGate(
    // A reconnect hands out a new communicator: start over with it.
    builder: (context, device) =>
        _DeviceView(key: ObjectKey(device), device: device),
  );
}

class _DeviceView extends StatefulWidget {
  const _DeviceView({super.key, required this.device});

  final ChameleonCommunicator device;

  @override
  State<_DeviceView> createState() => _DeviceViewState();
}

class _DeviceViewState extends State<_DeviceView> {
  DeviceInfo? _info;
  bool _failed = false;
  bool _loading = false;
  int _generation = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++; // late answers are dropped
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    DeviceInfo? info;
    try {
      info = await DeviceInfo.read(widget.device);
    } catch (_) {}
    if (!mounted || gen != _generation) return;
    setState(() {
      _loading = false;
      _info = info ?? _info;
      _failed = info == null;
    });
  }

  Future<void> _disconnect() async {
    final connection = WearServicesScope.of(context).connection;
    final ok = await ConfirmDialog.show(
      context,
      title: DeviceStrings.disconnectTitle,
      message: DeviceStrings.disconnectMessage,
      confirmLabel: DeviceStrings.disconnect,
    );
    if (ok) await connection.disconnect();
  }

  Future<void> _forget() async {
    final connection = WearServicesScope.of(context).connection;
    final ok = await ConfirmDialog.show(
      context,
      title: DeviceStrings.forgetTitle,
      message: DeviceStrings.forgetMessage,
      confirmLabel: DeviceStrings.forget,
      destructive: true,
    );
    if (!ok) return;
    await connection.forgetLastDevice();
    await connection.disconnect();
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Widget _row(String label, String value) =>
      CompactListTile(title: value, subtitle: label);

  @override
  Widget build(BuildContext context) {
    final connection = WearServicesScope.of(context).connection;
    final active = connection.activeDevice;
    final info = _info;
    final theme = Theme.of(context);
    return RoundScaffold(
      title: DeviceStrings.title,
      children: [
        Center(
          child: StatusPill(
            label: DeviceStrings.connected,
            kind: StatusKind.ok,
            icon: Icons.bluetooth_connected,
          ),
        ),
        if (active != null) ...[
          _row(DeviceStrings.model, active.isUltra ? 'Ultra' : 'Lite'),
          _row(DeviceStrings.connection, active.id),
        ],
        if (info != null) ...[
          _row(
            DeviceStrings.firmware,
            info.legacyProtocol
                ? '${info.firmware} (${DeviceStrings.legacyFirmware})'
                : info.firmware,
          ),
          _row(
            DeviceStrings.battery,
            DeviceStrings.batteryValue(
              info.batteryPercent,
              info.batteryMillivolts,
            ),
          ),
          _row(
            DeviceStrings.mode,
            info.readerMode
                ? DeviceStrings.modeReader
                : DeviceStrings.modeEmulator,
          ),
          _row(
            DeviceStrings.activeSlot,
            DeviceStrings.slotValue(info.activeSlot),
          ),
        ] else if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              DeviceStrings.loadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        WearButton(
          label: DeviceStrings.refresh,
          icon: Icons.refresh,
          style: WearButtonStyle.tonal,
          onPressed: _loading ? null : _load,
        ),
        CompactListTile(
          title: DeviceStrings.settings,
          leading: const Icon(Icons.tune),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => _open(const DeviceSettingsPage()),
        ),
        CompactListTile(
          title: DeviceStrings.bluetooth,
          leading: const Icon(Icons.bluetooth),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => _open(const DeviceBlePage()),
        ),
        WearButton(
          label: DeviceStrings.disconnect,
          style: WearButtonStyle.tonal,
          onPressed: _disconnect,
        ),
        WearButton(
          label: DeviceStrings.forget,
          style: WearButtonStyle.destructive,
          onPressed: _forget,
        ),
      ],
    );
  }
}
