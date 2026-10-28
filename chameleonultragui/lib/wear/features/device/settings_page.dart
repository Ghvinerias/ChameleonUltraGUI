import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/wear/features/device/device_controller.dart';
import 'package:chameleonultragui/wear/features/device/device_widgets.dart';
import 'package:chameleonultragui/wear/features/device/strings.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Animation, buttons, long press time and wake time of the Chameleon.
class DeviceSettingsPage extends StatelessWidget {
  const DeviceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => WearConnectionGate(
    builder: (context, device) =>
        _SettingsView(key: ObjectKey(device), device: device),
  );
}

class _SettingsView extends StatefulWidget {
  const _SettingsView({super.key, required this.device});

  final ChameleonCommunicator device;

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  late final DeviceSettingsController _c = DeviceSettingsController(
    widget.device,
  )..load(withThreshold: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _buttonTile(
    String label,
    ButtonType type,
    ButtonConfig current,
    SettingKey key, {
    required bool long,
  }) => SettingTile(
    label: label,
    value: DeviceStrings.buttonLabel(current),
    status: _c.statusOf(key),
    onTap: () async {
      final v = await OptionPickerPage.show<ButtonConfig>(
        context,
        title: label,
        options: ButtonConfig.values,
        labelOf: DeviceStrings.buttonLabel,
        selected: current,
      );
      if (v != null && v != current) _c.setButton(type, v, long: long);
    },
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final s = _c.settings;
      if (s == null) {
        return RoundScaffold(
          title: DeviceStrings.settings,
          children: [
            if (_c.loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(
                DeviceStrings.loadFailed,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              WearButton(
                label: DeviceStrings.retry,
                onPressed: () => _c.load(withThreshold: true),
              ),
            ],
          ],
        );
      }
      return RoundScaffold(
        title: DeviceStrings.settings,
        children: [
          SettingTile(
            label: DeviceStrings.animation,
            value: DeviceStrings.animationLabel(s.animation),
            status: _c.statusOf(SettingKey.animation),
            onTap: () async {
              final v = await OptionPickerPage.show<AnimationSetting>(
                context,
                title: DeviceStrings.animation,
                options: AnimationSetting.values,
                labelOf: DeviceStrings.animationLabel,
                selected: s.animation,
              );
              if (v != null && v != s.animation) _c.setAnimation(v);
            },
          ),
          _buttonTile(
            DeviceStrings.buttonAShort,
            ButtonType.a,
            s.aPress,
            SettingKey.aPress,
            long: false,
          ),
          _buttonTile(
            DeviceStrings.buttonBShort,
            ButtonType.b,
            s.bPress,
            SettingKey.bPress,
            long: false,
          ),
          _buttonTile(
            DeviceStrings.buttonALong,
            ButtonType.a,
            s.aLongPress,
            SettingKey.aLongPress,
            long: true,
          ),
          _buttonTile(
            DeviceStrings.buttonBLong,
            ButtonType.b,
            s.bLongPress,
            SettingKey.bLongPress,
            long: true,
          ),
          if (_c.thresholdSupported && s.longPressThreshold != null)
            SettingTile(
              label: DeviceStrings.longPressThreshold,
              value: '${s.longPressThreshold} ${DeviceStrings.unitMs}',
              status: _c.statusOf(SettingKey.longPressThreshold),
              onTap: () async {
                // Same bounds as the phone's slider (the firmware accepts
                // 200..65535 but the useful range ends at 1800).
                final v = await StepperPage.show(
                  context,
                  title: DeviceStrings.longPressThreshold,
                  initial: s.longPressThreshold!,
                  min: 200,
                  max: 1800,
                  step: 50,
                  unit: DeviceStrings.unitMs,
                );
                if (v != null && v != s.longPressThreshold) {
                  _c.setLongPressThreshold(v);
                }
              },
            ),
          if (s.wakeTimeSeconds != null)
            SettingTile(
              label: DeviceStrings.wakeTime,
              value: '${s.wakeTimeSeconds} ${DeviceStrings.unitSeconds}',
              status: _c.statusOf(SettingKey.wakeTime),
              onTap: () async {
                // Phone validator: validateIntRange 5..60.
                final v = await StepperPage.show(
                  context,
                  title: DeviceStrings.wakeTime,
                  initial: s.wakeTimeSeconds!,
                  min: 5,
                  max: 60,
                  step: 5,
                  unit: DeviceStrings.unitSeconds,
                );
                if (v != null && v != s.wakeTimeSeconds) _c.setWakeTime(v);
              },
            ),
        ],
      );
    },
  );
}
