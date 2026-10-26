import 'dart:async';

import 'package:flutter/foundation.dart';

import 'apk_source.dart';
import 'watch_installer.dart';

enum WizardStep {
  checklist,
  pair,
  connect,
  apkSource,
  install,
  launch,
  aftercare,
}

/// Pure-Dart state machine behind the "Install on watch" wizard.
///
/// Flow: checklist -> pair -> connect -> apkSource -> install -> launch -> aftercare.
/// A failing operation keeps the wizard on its current step and records
/// [error]; the UI shows a hint per [WatchInstallErrorType] and the user retries
/// or goes [back].
class InstallWizardController extends ChangeNotifier {
  InstallWizardController({
    required this.installer,
    required this.fetcher,
    this.apkUrl = defaultWearApkUrl,
    this.packageName = watchPackageName,
  });

  final WatchInstaller installer;
  final ApkFetcher fetcher;
  String apkUrl;
  final String packageName;

  WizardStep _step = WizardStep.checklist;
  bool _busy = false;
  WatchInstallException? _error;
  double _progress = 0;
  String? _apkPath;
  String? host;
  WatchPackageVersion? _installedVersion;
  bool _forgotten = false;
  bool _disposed = false;
  StreamSubscription<double>? _progressSub;

  WizardStep get step => _step;
  bool get busy => _busy;
  WatchInstallException? get error => _error;
  double get progress => _progress;
  String? get apkPath => _apkPath;
  WatchPackageVersion? get installedVersion => _installedVersion;
  bool get forgotten => _forgotten;

  @override
  void dispose() {
    _disposed = true;
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<bool> _run(Future<void> Function() body) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on _Cancelled {
      return false;
    } on WatchInstallException catch (e) {
      _error = e;
      return false;
    } catch (e) {
      _error = WatchInstallException(WatchInstallErrorType.other, e.toString());
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _goTo(WizardStep s) {
    _step = s;
    _error = null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Prerequisites acknowledged by the user.
  void confirmChecklist() {
    if (_step != WizardStep.checklist) return;
    _goTo(WizardStep.pair);
    notifyListeners();
  }

  /// Already paired earlier (keys stored): skip straight to connecting.
  void skipPairing() {
    if (_step != WizardStep.pair) return;
    _goTo(WizardStep.connect);
    notifyListeners();
  }

  Future<void> pair(String host, int port, String code) async {
    if (_step != WizardStep.pair) return;
    this.host = host;
    final ok = await _run(() => installer.pair(host, port, code));
    if (ok) {
      _goTo(WizardStep.connect);
      notifyListeners();
    }
  }

  Future<void> connect(String host, int port) async {
    if (_step != WizardStep.connect) return;
    this.host = host;
    final ok = await _run(() async {
      await installer.connect(host, port);
      try {
        _installedVersion = await installer.installedVersion(packageName);
      } on WatchInstallException {
        _installedVersion = null; // purely informational
      }
    });
    if (ok) {
      _goTo(WizardStep.apkSource);
      notifyListeners();
    }
  }

  Future<void> useDownloadedApk([String? url]) async {
    if (_step != WizardStep.apkSource) return;
    if (url != null) apkUrl = url;
    final ok = await _run(() async {
      _apkPath = await fetcher.downloadZip(apkUrl);
    });
    if (ok) {
      _goTo(WizardStep.install);
      notifyListeners();
    }
  }

  Future<void> useLocalApk() async {
    if (_step != WizardStep.apkSource) return;
    final ok = await _run(() async {
      final path = await fetcher.pickLocal();
      if (path == null) throw _Cancelled();
      _apkPath = path;
    });
    if (ok) {
      _goTo(WizardStep.install);
      notifyListeners();
    }
  }

  Future<void> install() async {
    if (_step != WizardStep.install) return;
    final path = _apkPath;
    if (path == null) return;
    _progress = 0;
    _progressSub?.cancel();
    _progressSub = installer.installProgress.listen((p) {
      _progress = p.clamp(0.0, 1.0);
      notifyListeners();
    });
    final ok = await _run(() => installer.install(path));
    await _progressSub?.cancel();
    _progressSub = null;
    if (ok) {
      _progress = 1;
      _goTo(WizardStep.launch);
      notifyListeners();
    }
  }

  /// Recovery for [WatchInstallErrorType.signatureMismatch]: removes the app that
  /// has a different signature, then retries the install. Loses the app's data
  /// on the watch (the UI must say so before calling this).
  Future<void> uninstallAndReinstall() async {
    if (_step != WizardStep.install) return;
    final ok = await _run(() => installer.uninstall(packageName));
    if (ok) await install();
  }

  Future<void> launch() async {
    if (_step != WizardStep.launch) return;
    final ok = await _run(() => installer.launch(packageName));
    if (ok) {
      _goTo(WizardStep.aftercare);
      notifyListeners();
    }
  }

  /// Skip launching (e.g. launch failed and the user opens the app manually).
  void skipLaunch() {
    if (_step != WizardStep.launch) return;
    _goTo(WizardStep.aftercare);
    notifyListeners();
  }

  /// Delete stored keys and disconnect. Allowed from any step.
  Future<void> forgetWatch() async {
    final ok = await _run(() => installer.forgetKeys());
    if (ok) {
      _forgotten = true;
      _apkPath = null;
      _installedVersion = null;
      _goTo(WizardStep.checklist);
      notifyListeners();
    }
  }

  /// Leave the wizard: drop the connection but keep the keys.
  Future<void> finish() async {
    try {
      await installer.disconnect();
    } on WatchInstallException {
      // best effort
    }
  }

  /// Go to the previous step (for retrying after an error).
  void back() {
    if (_busy) return;
    final target = switch (_step) {
      WizardStep.checklist => WizardStep.checklist,
      WizardStep.pair => WizardStep.checklist,
      WizardStep.connect => WizardStep.pair,
      WizardStep.apkSource => WizardStep.connect,
      WizardStep.install => WizardStep.apkSource,
      WizardStep.launch => WizardStep.install,
      WizardStep.aftercare => WizardStep.aftercare,
    };
    _goTo(target);
    notifyListeners();
  }
}

/// Internal: user dismissed the file picker. Not an error for the UI.
class _Cancelled extends WatchInstallException {
  _Cancelled() : super(WatchInstallErrorType.other, 'cancelled');
}
