import 'package:chameleonultragui/helpers/definitions.dart';

import '../../../fakes/fake_chameleon_communicator.dart';

/// Fake Chameleon with the device-level commands the Device feature uses.
class DeviceFake extends FakeChameleonCommunicator {
  DeviceFake({this.withThreshold = true, this.withWake = true});

  final bool withThreshold;
  final bool withWake;

  /// Commands in order, e.g. `setAnimationMode(2)`, `saveSettings`.
  final List<String> cmds = [];

  /// Command names (before the parenthesis) that throw while in this set.
  final Set<String> failing = {};

  AnimationSetting animation = AnimationSetting.full;
  ButtonConfig aPress = ButtonConfig.cycleForward;
  ButtonConfig bPress = ButtonConfig.cycleBackward;
  ButtonConfig aLong = ButtonConfig.disable;
  ButtonConfig bLong = ButtonConfig.cloneUID;
  bool pairing = true;
  String key = '123456';
  int wake = 20;
  int threshold = 1000;
  int batteryPercent = 65;
  int batteryMv = 3940;

  void _do(String call) {
    cmds.add(call);
    if (failing.contains(call.split('(').first)) {
      throw StateError('injected failure: $call');
    }
  }

  List<String> get writes =>
      cmds.where((c) => c.startsWith('set') || c == 'saveSettings').toList();

  @override
  Future<FirmwareVersion> getFirmwareVersion() async {
    _do('getFirmwareVersion');
    return FirmwareVersion(legacyProtocol: false, version: 0x0202);
  }

  @override
  Future<BatteryCharge> getBatteryCharge() async {
    _do('getBatteryCharge');
    return BatteryCharge(voltage: batteryMv, percent: batteryPercent);
  }

  @override
  Future<bool> isReaderDeviceMode() async {
    _do('isReaderDeviceMode');
    return readerMode;
  }

  @override
  Future<int> getActiveSlot() async {
    _do('getActiveSlot');
    return activeSlot;
  }

  @override
  Future<DeviceSettings> getDeviceSettings() async {
    _do('getDeviceSettings');
    return DeviceSettings(
      animation: animation,
      aPress: aPress,
      bPress: bPress,
      aLongPress: aLong,
      bLongPress: bLong,
      pairingEnabled: pairing,
      key: key,
      wakeTimeSeconds: withWake ? wake : null,
    );
  }

  @override
  Future<List<int>> getDeviceCapabilities() async {
    _do('getDeviceCapabilities');
    return withThreshold ? [ChameleonCommand.getLongPressThreshold.value] : [];
  }

  @override
  Future<int> getLongPressThreshold() async {
    _do('getLongPressThreshold');
    return threshold;
  }

  @override
  Future<void> setAnimationMode(AnimationSetting a) async {
    _do('setAnimationMode(${a.value})');
    animation = a;
  }

  @override
  Future<void> setButtonConfig(ButtonType t, ButtonConfig m) async {
    _do('setButtonConfig(${t.name},${m.value})');
    if (t == ButtonType.a) {
      aPress = m;
    } else {
      bPress = m;
    }
  }

  @override
  Future<void> setLongButtonConfig(ButtonType t, ButtonConfig m) async {
    _do('setLongButtonConfig(${t.name},${m.value})');
    if (t == ButtonType.a) {
      aLong = m;
    } else {
      bLong = m;
    }
  }

  @override
  Future<void> setLongPressThreshold(int ms) async {
    _do('setLongPressThreshold($ms)');
    threshold = ms;
  }

  @override
  Future<void> setSleepTimeout(int seconds) async {
    _do('setSleepTimeout($seconds)');
    wake = seconds;
  }

  @override
  Future<void> setBLEPairEnabled(bool status) async {
    _do('setBLEPairEnabled($status)');
    pairing = status;
  }

  @override
  Future<void> setBLEConnectKey(String k) async {
    _do('setBLEConnectKey($k)');
    key = k;
  }

  @override
  Future<void> clearBLEBoundedDevices() async {
    _do('clearBLEBoundedDevices');
  }

  @override
  Future<void> saveSettings() async {
    _do('saveSettings');
  }
}
