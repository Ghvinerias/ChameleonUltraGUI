import 'dart:async';

import 'package:flutter/services.dart';

/// Failure categories reported by the native side.
enum AdbWifiErrorType {
  signatureMismatch('signature_mismatch'),
  noMatchingAbis('no_matching_abis'),
  connectionFailed('connection_failed'),
  pairingFailed('pairing_failed'),
  notConnected('not_connected'),
  other('other');

  const AdbWifiErrorType(this.code);
  final String code;

  static AdbWifiErrorType fromCode(String? code) => AdbWifiErrorType.values
      .firstWhere((e) => e.code == code, orElse: () => AdbWifiErrorType.other);
}

class AdbWifiException implements Exception {
  AdbWifiException(this.type, [this.message]);
  final AdbWifiErrorType type;
  final String? message;

  @override
  String toString() => 'AdbWifiException(${type.code}: $message)';
}

class InstalledVersion {
  const InstalledVersion({this.versionName, this.versionCode});
  final String? versionName;
  final int? versionCode;
}

class DeviceInfo {
  const DeviceInfo({this.model = '', this.abiList = '', this.sdk = ''});
  final String model;
  final String abiList;
  final String sdk;
}

class InstallProgressEvent {
  const InstallProgressEvent(this.sent, this.total);
  final int sent;
  final int total;
  double get fraction => total <= 0 ? 0 : (sent / total).clamp(0.0, 1.0);
}

/// Thin Dart wrapper over the Android ADB-over-Wi-Fi plugin (MethodChannel +
/// EventChannel). Android only.
class AdbWifi {
  AdbWifi();

  static const MethodChannel _method =
      MethodChannel('io.chameleon.ultra/adb_wifi');
  static const EventChannel _events =
      EventChannel('io.chameleon.ultra/adb_wifi/progress');

  Stream<InstallProgressEvent>? _progress;

  Stream<InstallProgressEvent> get installProgress => _progress ??= _events
      .receiveBroadcastStream()
      .where((e) => e is Map && e['op'] == 'install')
      .map((e) => InstallProgressEvent(
          (e['sent'] as num).toInt(), (e['total'] as num).toInt()));

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AdbWifiException(AdbWifiErrorType.fromCode(e.code), e.message);
    }
  }

  Future<void> pair(String host, int port, String code) =>
      _invoke('pair', {'host': host, 'port': port, 'code': code});

  Future<void> connect(String host, int port) =>
      _invoke('connect', {'host': host, 'port': port});

  Future<void> install(String apkPath) =>
      _invoke('install', {'apkPath': apkPath});

  Future<void> uninstall(String packageName) =>
      _invoke('uninstall', {'packageName': packageName});

  Future<void> launch(String packageName) =>
      _invoke('launch', {'packageName': packageName});

  Future<InstalledVersion?> installedVersion(String packageName) async {
    final r = await _invoke<Map<Object?, Object?>>(
        'installedVersion', {'packageName': packageName});
    if (r == null) return null;
    return InstalledVersion(
        versionName: r['versionName'] as String?,
        versionCode: (r['versionCode'] as num?)?.toInt());
  }

  Future<DeviceInfo> deviceInfo() async {
    final r = await _invoke<Map<Object?, Object?>>('deviceInfo');
    return DeviceInfo(
        model: (r?['model'] as String?) ?? '',
        abiList: (r?['abiList'] as String?) ?? '',
        sdk: (r?['sdk'] as String?) ?? '');
  }

  Future<bool> isConnected() async =>
      await _invoke<bool>('isConnected') ?? false;

  Future<bool> hasKeys() async => await _invoke<bool>('hasKeys') ?? false;

  Future<void> disconnect() => _invoke('disconnect');

  /// Disconnects and deletes the stored ADB key pair.
  Future<void> forgetKeys() => _invoke('forgetKeys');
}
