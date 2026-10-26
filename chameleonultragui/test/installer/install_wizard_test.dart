import 'dart:io';

import 'package:archive/archive.dart';
import 'package:chameleonultragui/installer/apk_source.dart';
import 'package:chameleonultragui/installer/install_wizard.dart';
import 'package:chameleonultragui/installer/watch_installer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_watch_installer.dart';

WatchInstallException err(WatchInstallErrorType t) =>
    WatchInstallException(t, 'boom');

void main() {
  late FakeWatchInstaller adb;
  late FakeApkFetcher fetcher;
  late InstallWizardController w;

  setUp(() {
    adb = FakeWatchInstaller();
    fetcher = FakeApkFetcher();
    w = InstallWizardController(installer: adb, fetcher: fetcher);
  });

  tearDown(() => w.dispose());

  Future<void> toConnect() async {
    w.confirmChecklist();
    await w.pair('192.168.1.5', 37625, '123456');
  }

  Future<void> toApkSource() async {
    await toConnect();
    await w.connect('192.168.1.5', 41593);
  }

  Future<void> toInstall({bool download = true}) async {
    await toApkSource();
    if (download) {
      await w.useDownloadedApk();
    } else {
      await w.useLocalApk();
    }
  }

  test('happy path with downloaded APK', () async {
    expect(w.step, WizardStep.checklist);
    adb.version = const WatchPackageVersion(versionName: '1.0', versionCode: 1);
    await toInstall();
    expect(w.step, WizardStep.install);
    expect(w.installedVersion?.versionName, '1.0');
    expect(fetcher.urls, [defaultWearApkUrl]);
    final seen = <double>[];
    w.addListener(() => seen.add(w.progress));
    await w.install();
    expect(w.step, WizardStep.launch);
    expect(w.progress, 1);
    expect(seen, containsAllInOrder([0.25, 0.5]));
    await w.launch();
    expect(w.step, WizardStep.aftercare);
    expect(w.error, isNull);
    expect(adb.calls, contains('launch io.chameleon.ultra'));
    await w.finish();
    expect(adb.connected, isFalse);
    expect(adb.keys, isTrue, reason: 'finish keeps keys');
  });

  test('happy path with local APK and custom URL', () async {
    await toApkSource();
    await w.useLocalApk();
    expect(w.step, WizardStep.install);
    expect(w.apkPath, '/tmp/local.apk');
    w.back();
    expect(w.step, WizardStep.apkSource);
    await w.useDownloadedApk('https://example.org/x.zip');
    expect(fetcher.urls, ['https://example.org/x.zip']);
  });

  test('skipPairing goes to connect', () {
    w.confirmChecklist();
    w.skipPairing();
    expect(w.step, WizardStep.connect);
  });

  test('picker cancelled is not an error', () async {
    await toApkSource();
    fetcher.pickResult = null;
    await w.useLocalApk();
    expect(w.step, WizardStep.apkSource);
    expect(w.error, isNull);
  });

  test('picker rejects non-apk', () async {
    await toApkSource();
    fetcher.pickError = err(WatchInstallErrorType.invalidApk);
    await w.useLocalApk();
    expect(w.step, WizardStep.apkSource);
    expect(w.error?.type, WatchInstallErrorType.invalidApk);
  });

  group('error paths', () {
    test('pairing failed stays on pair, retry succeeds', () async {
      adb.pairError = err(WatchInstallErrorType.pairingFailed);
      w.confirmChecklist();
      await w.pair('192.168.1.5', 37625, '000000');
      expect(w.step, WizardStep.pair);
      expect(w.error?.type, WatchInstallErrorType.pairingFailed);
      expect(w.busy, isFalse);
      adb.pairError = null;
      await w.pair('192.168.1.5', 37625, '123456');
      expect(w.step, WizardStep.connect);
      expect(w.error, isNull);
    });

    test('connection refused/timeout stays on connect', () async {
      adb.connectError = err(WatchInstallErrorType.connectionFailed);
      await toConnect();
      await w.connect('192.168.1.5', 1234);
      expect(w.step, WizardStep.connect);
      expect(w.error?.type, WatchInstallErrorType.connectionFailed);
      adb.connectError = null;
      await w.connect('192.168.1.5', 41593);
      expect(w.step, WizardStep.apkSource);
    });

    test('connect not trusted maps to pairing failed, back to pair', () async {
      adb.connectError = err(WatchInstallErrorType.pairingFailed);
      await toConnect();
      await w.connect('192.168.1.5', 41593);
      expect(w.error?.type, WatchInstallErrorType.pairingFailed);
      w.back();
      expect(w.step, WizardStep.pair);
      expect(w.error, isNull);
    });

    test('version query failure does not block connecting', () async {
      adb.versionError = err(WatchInstallErrorType.other);
      await toApkSource();
      expect(w.step, WizardStep.apkSource);
      expect(w.installedVersion, isNull);
    });

    test('download failed stays on apk source', () async {
      await toApkSource();
      fetcher.downloadError = err(WatchInstallErrorType.downloadFailed);
      await w.useDownloadedApk();
      expect(w.step, WizardStep.apkSource);
      expect(w.error?.type, WatchInstallErrorType.downloadFailed);
    });

    test('unexpected exception becomes other', () async {
      await toApkSource();
      final f = _ThrowingFetcher();
      final w2 = InstallWizardController(installer: adb, fetcher: f);
      addTearDown(w2.dispose);
      w2.confirmChecklist();
      await w2.pair('h', 1, 'c');
      await w2.connect('h', 2);
      await w2.useDownloadedApk();
      expect(w2.error?.type, WatchInstallErrorType.other);
    });

    test('signature mismatch: uninstall + reinstall recovers', () async {
      await toInstall();
      adb.installError = err(WatchInstallErrorType.signatureMismatch);
      await w.install();
      expect(w.step, WizardStep.install);
      expect(w.error?.type, WatchInstallErrorType.signatureMismatch);
      await w.uninstallAndReinstall();
      expect(adb.calls, contains('uninstall io.chameleon.ultra'));
      expect(w.step, WizardStep.launch);
      expect(w.error, isNull);
      expect(adb.installed, isTrue);
    });

    test('signature mismatch: uninstall failure is reported', () async {
      await toInstall();
      adb.installError = err(WatchInstallErrorType.signatureMismatch);
      adb.uninstallError = err(WatchInstallErrorType.other);
      await w.install();
      await w.uninstallAndReinstall();
      expect(w.step, WizardStep.install);
      expect(w.error?.type, WatchInstallErrorType.other);
    });

    test('no matching ABIs stays on install; choose another APK', () async {
      await toInstall();
      adb.installError = err(WatchInstallErrorType.noMatchingAbis);
      await w.install();
      expect(w.step, WizardStep.install);
      expect(w.error?.type, WatchInstallErrorType.noMatchingAbis);
      w.back();
      expect(w.step, WizardStep.apkSource);
      expect(w.error, isNull);
      adb.installError = null;
      await w.useLocalApk();
      await w.install();
      expect(w.step, WizardStep.launch);
    });

    test('connection lost during install', () async {
      await toInstall();
      adb.installError = err(WatchInstallErrorType.connectionFailed);
      await w.install();
      expect(w.error?.type, WatchInstallErrorType.connectionFailed);
      expect(w.step, WizardStep.install);
      expect(w.busy, isFalse);
    });

    test('not connected at install time', () async {
      await toInstall();
      adb.connected = false;
      await w.install();
      expect(w.error?.type, WatchInstallErrorType.notConnected);
    });

    test('other install failure', () async {
      await toInstall();
      adb.installError = err(WatchInstallErrorType.other);
      await w.install();
      expect(w.error?.type, WatchInstallErrorType.other);
      adb.installError = null;
      await w.install();
      expect(w.step, WizardStep.launch);
    });

    test('launch failure: retry or skip', () async {
      await toInstall();
      await w.install();
      adb.launchError = err(WatchInstallErrorType.other);
      await w.launch();
      expect(w.step, WizardStep.launch);
      expect(w.error?.type, WatchInstallErrorType.other);
      w.skipLaunch();
      expect(w.step, WizardStep.aftercare);
      expect(w.error, isNull);
    });
  });

  group('forget watch', () {
    test('clears keys and restarts the wizard', () async {
      await toInstall();
      await w.install();
      await w.launch();
      await w.forgetWatch();
      expect(adb.keys, isFalse);
      expect(w.forgotten, isTrue);
      expect(w.step, WizardStep.checklist);
      expect(w.apkPath, isNull);
    });

    test('failure is surfaced', () async {
      adb.forgetError = err(WatchInstallErrorType.other);
      await w.forgetWatch();
      expect(w.error?.type, WatchInstallErrorType.other);
      expect(w.forgotten, isFalse);
    });
  });

  test('steps are guarded: wrong-step calls are ignored', () async {
    await w.pair('h', 1, 'c');
    await w.connect('h', 1);
    await w.install();
    await w.launch();
    expect(w.step, WizardStep.checklist);
    expect(adb.calls, isEmpty);
  });

  group('zip extraction', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('apkzip-test'));
    tearDown(() => dir.deleteSync(recursive: true));

    List<int> zip(Map<String, List<int>> files) {
      final a = Archive();
      files.forEach((n, c) => a.addFile(ArchiveFile(n, c.length, c)));
      return ZipEncoder().encode(a);
    }

    test('extracts the apk from a directory inside the zip', () async {
      final path = await extractApkFromZip(
        zip({
          'wear-apk/app-wear-release.apk': [1, 2, 3],
          'wear-apk/x.txt': [9],
        }),
        dir,
      );
      expect(path, '${dir.path}/app-wear-release.apk');
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('ignores path traversal in entry names', () async {
      final path = await extractApkFromZip(
        zip({
          '../../evil.apk': [7],
        }),
        dir,
      );
      expect(path, '${dir.path}/evil.apk');
    });

    test('zip without apk and non-zip data fail as downloadFailed', () async {
      await expectLater(
        extractApkFromZip(
          zip({
            'a.txt': [1],
          }),
          dir,
        ),
        throwsA(
          isA<WatchInstallException>().having(
            (e) => e.type,
            'type',
            WatchInstallErrorType.downloadFailed,
          ),
        ),
      );
      await expectLater(
        extractApkFromZip([1, 2, 3], dir),
        throwsA(
          isA<WatchInstallException>().having(
            (e) => e.type,
            'type',
            WatchInstallErrorType.downloadFailed,
          ),
        ),
      );
    });
  });
}

class _ThrowingFetcher implements ApkFetcher {
  @override
  Future<String> downloadZip(String url) async => throw StateError('x');
  @override
  Future<String?> pickLocal() async => null;
}
