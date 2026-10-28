import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';

/// Snapshot of the "Device" page, fetched with four commands.
class DeviceInfo {
  const DeviceInfo({
    required this.firmware,
    required this.legacyProtocol,
    required this.batteryPercent,
    required this.batteryMillivolts,
    required this.readerMode,
    required this.activeSlot,
  });

  final String firmware;
  final bool legacyProtocol;
  final int batteryPercent;
  final int batteryMillivolts;
  final bool readerMode;

  /// 0-based.
  final int activeSlot;

  /// Firmware version, battery, mode and active slot. The model (Ultra/Lite)
  /// is known from the scan, so it costs no command.
  static Future<DeviceInfo> read(ChameleonCommunicator device) async {
    final fw = await device.getFirmwareVersion();
    final battery = await device.getBatteryCharge();
    final reader = await device.isReaderDeviceMode();
    final slot = await device.getActiveSlot();
    return DeviceInfo(
      firmware: numToVerCode(fw.version),
      legacyProtocol: fw.legacyProtocol,
      batteryPercent: battery.percent,
      batteryMillivolts: battery.voltage,
      readerMode: reader,
      activeSlot: slot,
    );
  }
}

enum SettingKey {
  animation,
  aPress,
  bPress,
  aLongPress,
  bLongPress,
  longPressThreshold,
  wakeTime,
  pairing,
  key,
}

enum SaveStatus { idle, saving, saved, failed }

/// Device settings: read once, write on change, revert when the write fails.
///
/// Every change is `set...` followed by `saveSettings` (as the phone dialog
/// does), applied optimistically and rolled back if either command fails.
/// Writes are serialized so two quick changes never interleave on the link.
class DeviceSettingsController extends ChangeNotifier {
  DeviceSettingsController(this.device);

  final ChameleonCommunicator device;

  DeviceSettings? settings;
  Object? loadError;
  bool loading = false;

  /// Long press threshold needs a newer firmware (see `getDeviceCapabilities`).
  bool thresholdSupported = false;

  final Map<SettingKey, SaveStatus> _status = {};
  Future<void> _tail = Future.value();
  bool _disposed = false;

  SaveStatus statusOf(SettingKey key) => _status[key] ?? SaveStatus.idle;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the settings (one command) and, with [withThreshold], the long
  /// press threshold when the firmware advertises it (two more commands).
  Future<void> load({bool withThreshold = false}) async {
    loading = true;
    loadError = null;
    _notify();
    try {
      final s = await device.getDeviceSettings();
      if (withThreshold) {
        // Not part of the settings payload; older firmware lacks it.
        try {
          final caps = await device.getDeviceCapabilities();
          if (caps.contains(ChameleonCommand.getLongPressThreshold.value)) {
            s.longPressThreshold = await device.getLongPressThreshold();
            thresholdSupported = true;
          }
        } catch (_) {
          thresholdSupported = false;
        }
      }
      settings = s;
    } catch (e) {
      loadError = e;
    }
    loading = false;
    _notify();
  }

  Future<bool> _change(
    SettingKey key,
    Future<void> Function() send,
    void Function() apply,
    void Function() revert,
  ) {
    if (statusOf(key) == SaveStatus.saving || settings == null) {
      return Future.value(false);
    }
    apply();
    _status[key] = SaveStatus.saving;
    _notify();
    final run = _tail.then((_) async {
      try {
        await send();
        await device.saveSettings();
        _status[key] = SaveStatus.saved;
        _notify();
        return true;
      } catch (_) {
        revert();
        _status[key] = SaveStatus.failed;
        _notify();
        return false;
      }
    });
    _tail = run.then((_) {});
    return run;
  }

  Future<bool> setAnimation(AnimationSetting value) {
    final old = settings!.animation;
    return _change(
      SettingKey.animation,
      () => device.setAnimationMode(value),
      () => settings!.animation = value,
      () => settings!.animation = old,
    );
  }

  Future<bool> setButton(
    ButtonType type,
    ButtonConfig value, {
    required bool long,
  }) {
    final s = settings!;
    final key = switch ((type, long)) {
      (ButtonType.a, false) => SettingKey.aPress,
      (ButtonType.b, false) => SettingKey.bPress,
      (ButtonType.a, true) => SettingKey.aLongPress,
      (ButtonType.b, true) => SettingKey.bLongPress,
    };
    ButtonConfig get() => switch (key) {
      SettingKey.aPress => s.aPress,
      SettingKey.bPress => s.bPress,
      SettingKey.aLongPress => s.aLongPress,
      _ => s.bLongPress,
    };
    void put(ButtonConfig v) {
      switch (key) {
        case SettingKey.aPress:
          s.aPress = v;
        case SettingKey.bPress:
          s.bPress = v;
        case SettingKey.aLongPress:
          s.aLongPress = v;
        default:
          s.bLongPress = v;
      }
    }

    final old = get();
    return _change(
      key,
      () => long
          ? device.setLongButtonConfig(type, value)
          : device.setButtonConfig(type, value),
      () => put(value),
      () => put(old),
    );
  }

  Future<bool> setLongPressThreshold(int ms) {
    final old = settings!.longPressThreshold;
    return _change(
      SettingKey.longPressThreshold,
      () => device.setLongPressThreshold(ms),
      () => settings!.longPressThreshold = ms,
      () => settings!.longPressThreshold = old,
    );
  }

  Future<bool> setWakeTime(int seconds) {
    final old = settings!.wakeTimeSeconds;
    return _change(
      SettingKey.wakeTime,
      () => device.setSleepTimeout(seconds),
      () => settings!.wakeTimeSeconds = seconds,
      () => settings!.wakeTimeSeconds = old,
    );
  }

  Future<bool> setPairing(bool enabled) {
    final old = settings!.pairingEnabled;
    return _change(
      SettingKey.pairing,
      () => device.setBLEPairEnabled(enabled),
      () => settings!.pairingEnabled = enabled,
      () => settings!.pairingEnabled = old,
    );
  }

  Future<bool> setPairingKey(String pin) {
    final old = settings!.key;
    return _change(
      SettingKey.key,
      () => device.setBLEConnectKey(pin),
      () => settings!.key = pin,
      () => settings!.key = old,
    );
  }

  /// Removes every bonded device on the Chameleon. The caller disconnects.
  Future<bool> clearBonds() async {
    try {
      await device.clearBLEBoundedDevices();
      return true;
    } catch (_) {
      return false;
    }
  }
}
