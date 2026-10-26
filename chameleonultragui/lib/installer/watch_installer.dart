import 'dart:async';

import 'package:adb_wifi/adb_wifi.dart';

/// Application id of the watch build (same as the phone, see Wear OS plan D2).
const String watchPackageName = 'io.chameleon.ultra';

/// Default location of the CI-built watch APK bundle.
const String defaultWearApkUrl =
    'https://github.com/Ghvinerias/ChameleonUltraGUI/releases/download/dev/wear-apk.zip';

enum WatchInstallErrorType {
  /// INSTALL_FAILED_UPDATE_INCOMPATIBLE: installed app has a different signing key.
  signatureMismatch,

  /// INSTALL_FAILED_NO_MATCHING_ABIS.
  noMatchingAbis,

  /// Connection refused / timeout / wireless debugging switched off.
  connectionFailed,

  /// Pairing code wrong or expired, or the phone key is not (or no longer) trusted.
  pairingFailed,

  /// An operation needing a connection was attempted without one.
  notConnected,

  /// APK download or extraction failed.
  downloadFailed,

  /// The chosen file is not a usable APK.
  invalidApk,

  other,
}

class WatchInstallException implements Exception {
  WatchInstallException(this.type, [this.message]);
  final WatchInstallErrorType type;
  final String? message;

  @override
  String toString() => 'WatchInstallException(${type.name}: $message)';
}

class WatchPackageVersion {
  const WatchPackageVersion({this.versionName, this.versionCode});
  final String? versionName;
  final int? versionCode;
}

/// Installs the Wear OS build onto a watch. Contract is owned by Track 0D.
///
/// All methods throw [WatchInstallException] on failure.
abstract class WatchInstaller {
  /// Install progress in the range 0..1 (emitted while [install] runs).
  Stream<double> get installProgress;

  /// Wireless-debugging pairing (pairing port + 6 digit code).
  Future<void> pair(String host, int port, String code);

  /// Connects to the watch's wireless debugging connect port.
  Future<void> connect(String host, int port);

  /// `adb install -r` of a local APK file.
  Future<void> install(String apkPath);

  Future<void> uninstall(String packageName);

  Future<void> launch(String packageName);

  /// Installed version of [packageName] on the watch, or null if not installed.
  Future<WatchPackageVersion?> installedVersion(String packageName);

  /// Whether this phone already holds an ADB key (i.e. may have paired before).
  Future<bool> hasKeys();

  Future<void> disconnect();

  /// Disconnects and deletes the stored ADB key pair.
  Future<void> forgetKeys();
}

/// [WatchInstaller] backed by the Kadb-based `adb_wifi` Android plugin.
class AdbWifiInstaller implements WatchInstaller {
  AdbWifiInstaller([AdbWifi? plugin]) : _plugin = plugin ?? AdbWifi();
  final AdbWifi _plugin;

  static WatchInstallErrorType _map(AdbWifiErrorType t) => switch (t) {
    AdbWifiErrorType.signatureMismatch =>
      WatchInstallErrorType.signatureMismatch,
    AdbWifiErrorType.noMatchingAbis => WatchInstallErrorType.noMatchingAbis,
    AdbWifiErrorType.connectionFailed => WatchInstallErrorType.connectionFailed,
    AdbWifiErrorType.pairingFailed => WatchInstallErrorType.pairingFailed,
    AdbWifiErrorType.notConnected => WatchInstallErrorType.notConnected,
    AdbWifiErrorType.other => WatchInstallErrorType.other,
  };

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AdbWifiException catch (e) {
      throw WatchInstallException(_map(e.type), e.message);
    }
  }

  @override
  Stream<double> get installProgress =>
      _plugin.installProgress.map((e) => e.fraction);

  @override
  Future<void> pair(String host, int port, String code) =>
      _guard(() => _plugin.pair(host, port, code));

  @override
  Future<void> connect(String host, int port) =>
      _guard(() => _plugin.connect(host, port));

  @override
  Future<void> install(String apkPath) =>
      _guard(() => _plugin.install(apkPath));

  @override
  Future<void> uninstall(String packageName) =>
      _guard(() => _plugin.uninstall(packageName));

  @override
  Future<void> launch(String packageName) =>
      _guard(() => _plugin.launch(packageName));

  @override
  Future<WatchPackageVersion?> installedVersion(String packageName) =>
      _guard(() async {
        final v = await _plugin.installedVersion(packageName);
        return v == null
            ? null
            : WatchPackageVersion(
                versionName: v.versionName,
                versionCode: v.versionCode,
              );
      });

  @override
  Future<bool> hasKeys() => _guard(_plugin.hasKeys);

  @override
  Future<void> disconnect() => _guard(_plugin.disconnect);

  @override
  Future<void> forgetKeys() => _guard(_plugin.forgetKeys);
}
