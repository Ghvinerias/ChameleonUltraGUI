import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:permission_handler/permission_handler.dart';

enum WearConnectionState {
  idle,
  permissionNeeded,
  scanning,
  devicesFound,
  connecting,
  connected,
  reconnecting,
  failed,
}

/// Machine-readable error; the UI maps it to text.
enum WearConnectionError {
  none,
  permissionDenied,
  permissionPermanentlyDenied,
  scanFailed,
  noDeviceFound,
  dfuDevice,
  connectFailed,
  connectionLost,
}

/// A Chameleon seen during a scan.
class WearDevice {
  final String id;
  final ChameleonDevice type;
  final bool dfu;

  const WearDevice({required this.id, required this.type, required this.dfu});

  bool get isUltra => type == ChameleonDevice.ultra;
  bool get isLite => type == ChameleonDevice.lite;

  /// Short display name, e.g. "Ultra ..A1B2".
  String get name {
    final base = isUltra ? 'Ultra' : 'Lite';
    final tail = id.length > 4 ? id.substring(id.length - 5) : id;
    return '$base ..$tail${dfu ? ' (DFU)' : ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is WearDevice &&
      other.id == id &&
      other.type == type &&
      other.dfu == dfu;

  @override
  int get hashCode => Object.hash(id, type, dfu);
}

/// Tunable timings and limits.
class WearConnectionPolicy {
  /// Upper bound for one scan (BLESerial itself scans for 2 s).
  final Duration scanTimeout;

  /// Upper bound for one `connectSpecificDevice` (BLESerial retries 5 times).
  final Duration connectTimeout;

  /// Timeout of the battery-query liveness check.
  final Duration livenessTimeout;

  /// First reconnect delay; doubles every attempt up to [backoffMax].
  final Duration backoffInitial;
  final Duration backoffMax;

  /// Reconnect attempts before giving up with `failed`.
  final int maxReconnectAttempts;

  const WearConnectionPolicy({
    this.scanTimeout = const Duration(seconds: 15),
    this.connectTimeout = const Duration(seconds: 45),
    this.livenessTimeout = const Duration(seconds: 4),
    this.backoffInitial = const Duration(seconds: 1),
    this.backoffMax = const Duration(seconds: 30),
    this.maxReconnectAttempts = 6,
  });

  Duration backoffFor(int attempt) {
    var d = backoffInitial;
    for (var i = 0; i < attempt; i++) {
      d *= 2;
      if (d >= backoffMax) return backoffMax;
    }
    return d >= backoffMax ? backoffMax : d;
  }
}

enum WearPermissionResult { granted, denied, permanentlyDenied }

/// Bluetooth runtime permissions (SCAN + CONNECT). Injectable for tests.
abstract class WearPermissions {
  Future<bool> isGranted();
  Future<WearPermissionResult> request();
  Future<void> openSettings();
}

class PermissionHandlerWearPermissions implements WearPermissions {
  const PermissionHandlerWearPermissions();

  static final _perms = [Permission.bluetoothScan, Permission.bluetoothConnect];

  @override
  Future<bool> isGranted() async {
    for (final p in _perms) {
      if (!await p.isGranted) return false;
    }
    return true;
  }

  @override
  Future<WearPermissionResult> request() async {
    final res = await _perms.request();
    if (res.values.every((s) => s.isGranted)) {
      return WearPermissionResult.granted;
    }
    if (res.values.any((s) => s.isPermanentlyDenied)) {
      return WearPermissionResult.permanentlyDenied;
    }
    return WearPermissionResult.denied;
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
