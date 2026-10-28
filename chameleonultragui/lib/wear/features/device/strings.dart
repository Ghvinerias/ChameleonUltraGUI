import 'package:chameleonultragui/helpers/definitions.dart';

/// English strings of the Device feature (kept out of the .arb files).
class DeviceStrings {
  DeviceStrings._();

  static const title = 'Device';
  static const refresh = 'Refresh';
  static const loading = 'Reading device...';
  static const loadFailed = 'Could not read the device';
  static const retry = 'Retry';

  static const model = 'Model';
  static const firmware = 'Firmware';
  static const battery = 'Battery';
  static const mode = 'Mode';
  static const activeSlot = 'Active slot';
  static const connection = 'Connection';
  static const connected = 'Connected';
  static const reconnecting = 'Reconnecting';
  static const modeReader = 'Reader';
  static const modeEmulator = 'Emulator';
  static const legacyFirmware = 'legacy';

  static String batteryValue(int percent, int millivolts) =>
      '$percent% · ${(millivolts / 1000).toStringAsFixed(2)} V';
  static String slotValue(int index) => '${index + 1}';

  static const settings = 'Settings';
  static const bluetooth = 'Bluetooth & security';

  static const disconnect = 'Disconnect';
  static const disconnectTitle = 'Disconnect?';
  static const disconnectMessage =
      'The watch will disconnect from the Chameleon.';
  static const forget = 'Forget this device';
  static const forgetTitle = 'Forget device?';
  static const forgetMessage =
      'The watch will disconnect and stop reconnecting to this Chameleon '
      'automatically.';

  // Settings
  static const animation = 'Animation';
  static const buttons = 'Buttons';
  static const buttonAShort = 'Button A, short press';
  static const buttonBShort = 'Button B, short press';
  static const buttonALong = 'Button A, long press';
  static const buttonBLong = 'Button B, long press';
  static const longPressThreshold = 'Long press time';
  static const wakeTime = 'Wake time after button press';
  static const unitMs = 'ms';
  static const unitSeconds = 's';
  static const saveValue = 'Save';
  static const saving = 'Saving...';
  static const saved = 'Saved';
  static const saveFailed = 'Not saved, reverted';

  static String animationLabel(AnimationSetting a) => switch (a) {
    AnimationSetting.full => 'Full',
    AnimationSetting.minimal => 'Mini',
    AnimationSetting.none => 'None',
    AnimationSetting.symmetric => 'Symmetric',
  };

  static String buttonLabel(ButtonConfig c) => switch (c) {
    ButtonConfig.disable => 'Disabled',
    ButtonConfig.cycleForward => 'Cycle forward',
    ButtonConfig.cycleBackward => 'Cycle backward',
    ButtonConfig.cloneUID => 'Clone UID',
    ButtonConfig.chargeStatus => 'Charge status',
  };

  // Bluetooth
  static const pairing = 'BLE pairing';
  static const pairingOn = 'Enabled';
  static const pairingOff = 'Disabled';
  static const changeKey = 'Change pairing key';
  static const changeKeySubtitle = '6-digit PIN';
  static const changeKeyTitle = 'Change PIN?';
  static const changeKeyMessage =
      'Phones and watches paired with the old PIN may no longer be able to '
      'connect until you enter the new one.';
  static const continueLabel = 'Continue';
  static const pinTitle = 'New PIN';
  static const pinSet = 'Set PIN';
  static const pinSaved = 'PIN changed';
  static const clearBonds = 'Clear bonded devices';
  static const clearBondsTitle = 'Clear bonds?';
  static const clearBondsMessage =
      'Every paired phone and watch is forgotten and must pair again. '
      'You can be locked out until you re-pair. This watch will disconnect.';
  static const clearBondsFailed = 'Could not clear bonds';
  static const unavailable = 'Not supported by this firmware';
}
