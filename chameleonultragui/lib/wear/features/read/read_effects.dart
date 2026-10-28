import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Platform side effects of the Read feature, injectable so tests do not need
/// the wakelock plugin or the haptics channel.
class ReadEffects {
  const ReadEffects({
    this.setKeepAwake = _defaultKeepAwake,
    this.hapticFound = _defaultHaptic,
  });

  /// Turns the screen keep-awake flag on or off. Must never throw.
  final Future<void> Function(bool enabled) setKeepAwake;

  /// Short vibration when a card is found.
  final Future<void> Function() hapticFound;

  static Future<void> _defaultKeepAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // Missing plugin (tests) or platform failure: keeping the screen on is
      // a convenience, never a reason to fail a scan.
    }
  }

  static Future<void> _defaultHaptic() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}
