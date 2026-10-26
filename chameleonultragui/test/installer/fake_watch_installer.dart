import 'dart:async';

import 'package:chameleonultragui/installer/apk_source.dart';
import 'package:chameleonultragui/installer/watch_installer.dart';

/// Scriptable [WatchInstaller]: set `*Error` fields to make a call fail.
class FakeWatchInstaller implements WatchInstaller {
  WatchInstallException? pairError;
  WatchInstallException? connectError;
  WatchInstallException? installError;
  WatchInstallException? uninstallError;
  WatchInstallException? launchError;
  WatchInstallException? versionError;
  WatchInstallException? forgetError;
  WatchPackageVersion? version;
  bool keys = false;
  bool connected = false;
  bool installed = false;

  /// Progress values emitted during a successful or failing [install].
  List<double> progressScript = [0.25, 0.5, 1.0];

  final List<String> calls = [];
  final _progress = StreamController<double>.broadcast();

  @override
  Stream<double> get installProgress => _progress.stream;

  @override
  Future<void> pair(String host, int port, String code) async {
    calls.add('pair $host:$port $code');
    if (pairError != null) throw pairError!;
    keys = true;
  }

  @override
  Future<void> connect(String host, int port) async {
    calls.add('connect $host:$port');
    if (connectError != null) throw connectError!;
    connected = true;
  }

  @override
  Future<void> install(String apkPath) async {
    calls.add('install $apkPath');
    if (!connected) {
      throw WatchInstallException(WatchInstallErrorType.notConnected);
    }
    for (final p in progressScript) {
      _progress.add(p);
      await Future<void>.delayed(Duration.zero);
    }
    if (installError != null) throw installError!;
    installed = true;
  }

  @override
  Future<void> uninstall(String packageName) async {
    calls.add('uninstall $packageName');
    if (uninstallError != null) throw uninstallError!;
    // Models the real recovery: after uninstalling, the signature clash is gone.
    installed = false;
    installError = null;
  }

  @override
  Future<void> launch(String packageName) async {
    calls.add('launch $packageName');
    if (launchError != null) throw launchError!;
  }

  @override
  Future<WatchPackageVersion?> installedVersion(String packageName) async {
    calls.add('version $packageName');
    if (versionError != null) throw versionError!;
    return version;
  }

  @override
  Future<bool> hasKeys() async => keys;

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    connected = false;
  }

  @override
  Future<void> forgetKeys() async {
    calls.add('forget');
    if (forgetError != null) throw forgetError!;
    keys = false;
    connected = false;
  }
}

class FakeApkFetcher implements ApkFetcher {
  WatchInstallException? downloadError;
  WatchInstallException? pickError;
  String? pickResult = '/tmp/local.apk';
  final List<String> urls = [];

  @override
  Future<String> downloadZip(String url) async {
    urls.add(url);
    if (downloadError != null) throw downloadError!;
    return '/tmp/downloaded/app-wear-release.apk';
  }

  @override
  Future<String?> pickLocal() async {
    if (pickError != null) throw pickError!;
    return pickResult;
  }
}
