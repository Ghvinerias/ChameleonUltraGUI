import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/wear/features/device/device_controller.dart';
import 'package:chameleonultragui/wear/features/device/device_widgets.dart';
import 'package:chameleonultragui/wear/features/device/strings.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// BLE pairing switch, pairing key and bond clearing. The key and bond
/// actions can lock other phones out, so both sit behind a ConfirmDialog.
class DeviceBlePage extends StatelessWidget {
  const DeviceBlePage({super.key});

  @override
  Widget build(BuildContext context) => WearConnectionGate(
    builder: (context, device) =>
        _BleView(key: ObjectKey(device), device: device),
  );
}

class _BleView extends StatefulWidget {
  const _BleView({super.key, required this.device});

  final ChameleonCommunicator device;

  @override
  State<_BleView> createState() => _BleViewState();
}

class _BleViewState extends State<_BleView> {
  late final DeviceSettingsController _c = DeviceSettingsController(
    widget.device,
  )..load();

  /// Short result line shown at the top.
  String? _message;
  bool _messageOk = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _say(String text, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageOk = ok;
    });
  }

  Future<void> _changeKey() async {
    final ok = await ConfirmDialog.show(
      context,
      title: DeviceStrings.changeKeyTitle,
      message: DeviceStrings.changeKeyMessage,
      confirmLabel: DeviceStrings.continueLabel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final pin = await PinEntryPage.show(context);
    if (pin == null || !mounted) return;
    final saved = await _c.setPairingKey(pin);
    _say(saved ? DeviceStrings.pinSaved : DeviceStrings.saveFailed, ok: saved);
  }

  Future<void> _clearBonds() async {
    final connection = WearServicesScope.of(context).connection;
    final ok = await ConfirmDialog.show(
      context,
      title: DeviceStrings.clearBondsTitle,
      message: DeviceStrings.clearBondsMessage,
      confirmLabel: DeviceStrings.clearBonds,
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await _c.clearBonds()) {
      // Like the phone: the link is bonded, so drop it.
      await connection.disconnect();
    } else {
      _say(DeviceStrings.clearBondsFailed, ok: false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final s = _c.settings;
      if (s == null) {
        return RoundScaffold(
          title: DeviceStrings.bluetooth,
          children: [
            if (_c.loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(
                DeviceStrings.loadFailed,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              WearButton(label: DeviceStrings.retry, onPressed: _c.load),
            ],
          ],
        );
      }
      return RoundScaffold(
        title: DeviceStrings.bluetooth,
        children: [
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Center(
                child: StatusPill(
                  label: _message!,
                  kind: _messageOk ? StatusKind.ok : StatusKind.error,
                ),
              ),
            ),
          SettingTile(
            label: DeviceStrings.pairing,
            value: s.pairingEnabled
                ? DeviceStrings.pairingOn
                : DeviceStrings.pairingOff,
            status: _c.statusOf(SettingKey.pairing),
            onTap: () => _c.setPairing(!s.pairingEnabled),
          ),
          // Like the phone dialog, key and bonds only matter with pairing on.
          if (s.pairingEnabled) ...[
            SettingTile(
              label: DeviceStrings.changeKey,
              value: DeviceStrings.changeKeySubtitle,
              status: _c.statusOf(SettingKey.key),
              onTap: _changeKey,
            ),
            WearButton(
              label: DeviceStrings.clearBonds,
              style: WearButtonStyle.destructive,
              onPressed: _clearBonds,
            ),
          ],
        ],
      );
    },
  );
}
