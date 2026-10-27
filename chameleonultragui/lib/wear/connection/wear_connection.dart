import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/wear/connection/wear_connection_types.dart';
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:chameleonultragui/wear/connection/wear_connection_types.dart';

typedef WearSerialFactory = AbstractSerial Function(Logger log);
typedef WearCommunicatorFactory = ChameleonCommunicator Function(
  Logger log,
  AbstractSerial serial,
);

/// BLE-only connection manager for the watch. UI independent.
///
/// Note: `BLESerial.availableChameleons` drops any active link, so [scan] is
/// refused while connected/connecting/reconnecting. A fresh
/// [ChameleonCommunicator] is created for every (re)connection; listen to this
/// notifier and re-read [communicator] when [state] changes.
class WearConnection extends ChangeNotifier with WidgetsBindingObserver {
  static const lastDevicePrefKey = 'wear.lastDeviceId';

  final WearSerialFactory _serialFactory;
  final WearCommunicatorFactory _communicatorFactory;
  final WearPermissions _permissions;
  final WearConnectionPolicy policy;
  final Logger log;

  WearConnection({
    WearSerialFactory? serialFactory,
    WearCommunicatorFactory? communicatorFactory,
    WearPermissions? permissions,
    this.policy = const WearConnectionPolicy(),
    Logger? log,
  }) : _serialFactory =
           serialFactory ?? ((l) => BLESerial(log: l) as AbstractSerial),
       _communicatorFactory =
           communicatorFactory ?? ((l, s) => ChameleonCommunicator(l, port: s)),
       _permissions = permissions ?? const PermissionHandlerWearPermissions(),
       log = log ?? Logger(level: Level.warning);

  AbstractSerial? _serial;
  ChameleonCommunicator? _communicator;
  WearConnectionState _state = WearConnectionState.idle;
  WearConnectionError _error = WearConnectionError.none;
  List<WearDevice> _devices = const [];
  List<WearDevice> _dfuDevices = const [];
  WearDevice? _active;
  String? _lastDeviceId;
  bool _lastLoaded = false;
  String? _suppressedId;
  int _reconnectAttempt = 0;
  int _generation = 0; // bumped to cancel an in-flight reconnect loop
  bool _disposed = false;
  bool _observing = false;
  bool _checking = false;

  WearConnectionState get state => _state;
  WearConnectionError get lastError => _error;

  /// Non-DFU Chameleons from the last scan.
  List<WearDevice> get devices => List.unmodifiable(_devices);

  /// Chameleons in DFU mode from the last scan (not connectable).
  List<WearDevice> get dfuDevices => List.unmodifiable(_dfuDevices);

  /// Device we are (or were last) connected to.
  WearDevice? get activeDevice => _active;

  /// 1-based reconnect attempt while [state] is `reconnecting`, else 0.
  int get reconnectAttempt => _reconnectAttempt;

  /// Non-null only while [state] is `connected`.
  ChameleonCommunicator? get communicator =>
      _state == WearConnectionState.connected ? _communicator : null;

  bool get isConnected => _state == WearConnectionState.connected;

  String? get lastDeviceId => _lastDeviceId;

  bool isAutoReconnectSuppressed(String id) => _suppressedId == id;

  // ---- lifecycle -------------------------------------------------------

  /// Registers for app lifecycle events (re-check on resume).
  void attach() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    final s = _serial;
    if (s != null) {
      s.connectionStateCallback = null;
      unawaited(s.performDisconnect().catchError((_) => false));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onResume());
    }
  }

  /// Periodic timers are throttled while the screen is off, so verify the
  /// link when the app comes back.
  Future<void> onResume() async {
    switch (_state) {
      case WearConnectionState.connected:
        await checkConnection();
      case WearConnectionState.failed:
        if (_active != null && _error == WearConnectionError.connectionLost) {
          _startReconnect(_active!);
        }
      default:
        break;
    }
  }

  void _set(WearConnectionState s, [WearConnectionError? e]) {
    _state = s;
    if (e != null) _error = e;
    if (!_disposed) notifyListeners();
  }

  AbstractSerial _ensureSerial() {
    var s = _serial;
    if (s == null) {
      s = _serialFactory(log);
      s.connectionStateCallback = _onSerialStateChanged;
      _serial = s;
    }
    return s;
  }

  Future<void> _loadLast() async {
    if (_lastLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastDeviceId = prefs.getString(lastDevicePrefKey);
    } catch (e) {
      log.w('Could not read last device: $e');
    }
    _lastLoaded = true;
  }

  Future<void> _saveLast(String id) async {
    _lastDeviceId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastDevicePrefKey, id);
    } catch (e) {
      log.w('Could not save last device: $e');
    }
  }

  /// Forget the remembered device.
  Future<void> forgetLastDevice() async {
    _lastDeviceId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastDevicePrefKey);
    } catch (_) {}
    if (!_disposed) notifyListeners();
  }

  // ---- permissions -----------------------------------------------------

  /// Returns true when BLUETOOTH_SCAN and BLUETOOTH_CONNECT are granted.
  /// Otherwise state becomes `permissionNeeded` with an error.
  Future<bool> ensurePermissions() async {
    if (await _permissions.isGranted()) return true;
    final res = await _permissions.request();
    if (res == WearPermissionResult.granted) {
      if (_state == WearConnectionState.permissionNeeded) {
        _set(WearConnectionState.idle, WearConnectionError.none);
      }
      return true;
    }
    _set(
      WearConnectionState.permissionNeeded,
      res == WearPermissionResult.permanentlyDenied
          ? WearConnectionError.permissionPermanentlyDenied
          : WearConnectionError.permissionDenied,
    );
    return false;
  }

  Future<void> openPermissionSettings() => _permissions.openSettings();

  // ---- scan ------------------------------------------------------------

  bool get _canScan =>
      _state == WearConnectionState.idle ||
      _state == WearConnectionState.permissionNeeded ||
      _state == WearConnectionState.devicesFound ||
      _state == WearConnectionState.failed;

  /// Scans for Chameleons. Returns the connectable (non-DFU) devices.
  /// Refused (returns the previous list) while a link is active.
  Future<List<WearDevice>> scan() async {
    if (!_canScan) return devices;
    _generation++; // cancels a pending reconnect loop
    if (!await ensurePermissions()) return const [];
    await _loadLast();

    _set(WearConnectionState.scanning, WearConnectionError.none);
    List<Chameleon> found;
    try {
      found = await _ensureSerial()
          .availableChameleons(false)
          .timeout(policy.scanTimeout);
    } catch (e) {
      log.w('Scan failed: $e');
      _devices = const [];
      _dfuDevices = const [];
      _set(WearConnectionState.failed, WearConnectionError.scanFailed);
      return const [];
    }

    final all = found
        .map(
          (c) => WearDevice(id: c.port.toString(), type: c.device, dfu: c.dfu),
        )
        .toList();
    _devices = all.where((d) => !d.dfu).toList();
    _dfuDevices = all.where((d) => d.dfu).toList();

    // Suppression lasts until the device disappears from a scan.
    if (_suppressedId != null && !all.any((d) => d.id == _suppressedId)) {
      _suppressedId = null;
    }

    if (_devices.isEmpty) {
      _set(WearConnectionState.idle, WearConnectionError.noDeviceFound);
    } else {
      _set(WearConnectionState.devicesFound, WearConnectionError.none);
    }
    return devices;
  }

  // ---- connect ---------------------------------------------------------

  Future<bool> _attempt(WearDevice device) async {
    final serial = _ensureSerial();
    try {
      final ok = await serial
          .connectSpecificDevice(device.id)
          .timeout(policy.connectTimeout);
      if (!ok) return false;
    } catch (e) {
      log.w('Connect failed: $e');
      try {
        await serial.performDisconnect();
      } catch (_) {}
      return false;
    }
    _communicator = _communicatorFactory(log, serial);
    _active = device;
    return true;
  }

  /// Connects to a scanned device. Returns true on success.
  Future<bool> connect(WearDevice device) async {
    if (_state == WearConnectionState.connecting ||
        _state == WearConnectionState.scanning) {
      return false;
    }
    if (device.dfu) {
      _set(WearConnectionState.failed, WearConnectionError.dfuDevice);
      return false;
    }
    if (!await ensurePermissions()) return false;
    _generation++;
    final gen = _generation;
    _communicator = null;
    _set(WearConnectionState.connecting, WearConnectionError.none);
    final ok = await _attempt(device);
    if (gen != _generation || _disposed) {
      // superseded (disconnect/dispose while connecting)
      if (ok) {
        try {
          await _serial?.performDisconnect();
        } catch (_) {}
      }
      return false;
    }
    if (!ok) {
      _communicator = null;
      _set(WearConnectionState.failed, WearConnectionError.connectFailed);
      return false;
    }
    _suppressedId = null;
    _reconnectAttempt = 0;
    await _saveLast(device.id);
    _set(WearConnectionState.connected, WearConnectionError.none);
    return true;
  }

  /// Disconnects. `manual` (default) suppresses auto-reconnect/auto-connect
  /// to this device until it disappears from a scan.
  Future<void> disconnect({bool manual = true}) async {
    _generation++;
    final id = _active?.id;
    if (manual && id != null) _suppressedId = id;
    _communicator = null;
    _reconnectAttempt = 0;
    _set(WearConnectionState.idle, WearConnectionError.none);
    try {
      await _serial?.performDisconnect();
    } catch (e) {
      log.w('Disconnect error: $e');
    }
  }

  /// Permission -> scan -> connect to the remembered device if visible and
  /// not suppressed. Returns true when connected.
  Future<bool> autoConnect() async {
    if (!_canScan) return isConnected;
    final list = await scan();
    final id = _lastDeviceId;
    if (id == null || list.isEmpty) return false;
    for (final d in list) {
      if (d.id == id) {
        if (isAutoReconnectSuppressed(id)) return false;
        return connect(d);
      }
    }
    return false;
  }

  // ---- reconnect / liveness -------------------------------------------

  void _onSerialStateChanged() {
    if (_state == WearConnectionState.connected &&
        !(_serial?.connected ?? false)) {
      _handleLost();
    }
  }

  void _handleLost() {
    final device = _active;
    if (device == null || _state != WearConnectionState.connected) return;
    log.w('Unexpected disconnect from ${device.id}');
    _communicator = null;
    _startReconnect(device);
  }

  void _startReconnect(WearDevice device) {
    _generation++;
    _reconnectAttempt = 0;
    _set(WearConnectionState.reconnecting, WearConnectionError.none);
    unawaited(_reconnectLoop(device, _generation));
  }

  Future<void> _reconnectLoop(WearDevice device, int gen) async {
    for (var i = 0; i < policy.maxReconnectAttempts; i++) {
      await Future<void>.delayed(policy.backoffFor(i));
      if (gen != _generation || _disposed) return;
      _reconnectAttempt = i + 1;
      if (!_disposed) notifyListeners();
      final ok = await _attempt(device);
      if (gen != _generation || _disposed) {
        if (ok) {
          try {
            await _serial?.performDisconnect();
          } catch (_) {}
        }
        return;
      }
      if (ok) {
        _reconnectAttempt = 0;
        _set(WearConnectionState.connected, WearConnectionError.none);
        return;
      }
    }
    _communicator = null;
    _set(WearConnectionState.failed, WearConnectionError.connectionLost);
  }

  /// Battery query with timeout. True when the device answered.
  Future<bool> isAlive({Duration? timeout}) async {
    final c = communicator;
    if (c == null) return false;
    try {
      await c.getBatteryCharge().timeout(timeout ?? policy.livenessTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verifies the link; if dead, starts the reconnect policy.
  Future<bool> checkConnection() async {
    if (_state != WearConnectionState.connected) return false;
    if (_checking) return true;
    _checking = true;
    try {
      final gen = _generation;
      final alive = (_serial?.connected ?? false) && await isAlive();
      if (!alive &&
          gen == _generation &&
          _state == WearConnectionState.connected) {
        final d = _active;
        if (d != null) {
          try {
            await _serial?.performDisconnect();
          } catch (_) {}
          if (gen == _generation && _state == WearConnectionState.connected) {
            _communicator = null;
            _startReconnect(d);
          }
        }
      }
      return alive;
    } finally {
      _checking = false;
    }
  }
}
