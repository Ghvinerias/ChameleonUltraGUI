import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/wear/spike/spike_models.dart';
import 'package:chameleonultragui/wear/spike/spike_vectors.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Native rotary-bezel events forwarded by MainActivity (delta per detent).
const rotaryChannel = EventChannel('io.chameleon.ultra/rotary');

const defaultReportUrl = 'http://10.10.10.24:8001/report';
const _urlPrefKey = 'wear_spike_report_url';

/// Holds spike state, runs the checks and persists the report.
class SpikeController extends ChangeNotifier {
  SpikeController({Directory? storageDir})
      : storageDir = storageDir ?? Directory.systemTemp;

  final Directory storageDir;
  final DateTime mainStartedAt = DateTime.now();
  SpikeReport report = SpikeReport();
  String reportUrl = defaultReportUrl;
  String status = '';
  bool busy = false;

  // Rotary
  int scrollEvents = 0;
  int keyEvents = 0;
  int nativeRotaryEvents = 0;
  double nativeRotaryTotal = 0;
  String lastScroll = '-';
  String lastKey = '-';

  // BLE
  BLESerial? serial;
  ChameleonCommunicator? communicator;
  List<Chameleon> found = [];
  String keepAliveProgress = '';

  File get _reportFile => File('${storageDir.path}/wear_spike_report.json');
  File get _markerFile => File('${storageDir.path}/wear_spike_hardnested.marker');

  bool get previousHardnestedUnfinished => _markerFile.existsSync();

  void _set(String s) {
    status = s;
    notifyListeners();
  }

  void add(SpikeResult r) {
    report.add(r);
    notifyListeners();
  }

  Future<SpikeResult> _run(String name, Future<SpikeOutcome> Function() body,
      {Duration timeout = const Duration(seconds: 30)}) async {
    busy = true;
    _set('Running $name...');
    final r = await runSpikeCheck(name, body, timeout: timeout);
    busy = false;
    add(r);
    status = '$name: ${r.status.name}';
    notifyListeners();
    return r;
  }

  Future<void> loadSavedUrl() async {
    try {
      final p = await SharedPreferences.getInstance();
      reportUrl = p.getString(_urlPrefKey) ?? defaultReportUrl;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setReportUrl(String url) async {
    reportUrl = url.trim();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_urlPrefKey, reportUrl);
    } catch (_) {}
  }

  /// Time from main() to first frame, plus process age if /proc is readable.
  void recordFirstFrame() {
    report.notes['mainToFirstFrameMs'] =
        DateTime.now().difference(mainStartedAt).inMilliseconds;
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      final rest = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      final startTicks = int.parse(rest[19]); // field 22 overall
      final uptime =
          double.parse(File('/proc/uptime').readAsStringSync().split(' ')[0]);
      report.notes['processAgeAtFirstFrameMs'] =
          ((uptime - startTicks / 100) * 1000).round();
    } catch (e) {
      report.notes['processAgeAtFirstFrameMs'] = 'n/a: $e';
    }
  }

  // ---- a. device info ----
  Future<void> deviceInfo(MediaQueryData mq) => _run('device_info', () async {
        final abi = Abi.current().toString();
        final p = mq.padding;
        final vp = mq.viewPadding;
        final data = <String, dynamic>{
          'abi': abi,
          'os': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'processors': Platform.numberOfProcessors,
          'dart': Platform.version,
          'screenW': mq.size.width,
          'screenH': mq.size.height,
          'devicePixelRatio': mq.devicePixelRatio,
          'textScaler': mq.textScaler.toString(),
          'padding': p.toString(),
          'viewPadding': vp.toString(),
          'isRoundHint': (p == EdgeInsets.zero && vp == EdgeInsets.zero)
              ? 'unknown (no insets reported)'
              : 'insets reported',
          'memory': _memInfo(),
        };
        report.notes['device'] = data;
        return SpikeOutcome.ok(
            'ABI $abi, ${mq.size.width.round()}x${mq.size.height.round()} '
            '@${mq.devicePixelRatio}x, ${Platform.operatingSystemVersion}, '
            '${Platform.numberOfProcessors} cpu',
            data);
      });

  Map<String, String> _memInfo() {
    try {
      final out = <String, String>{};
      for (final line in File('/proc/meminfo').readAsLinesSync()) {
        if (line.startsWith('MemTotal') ||
            line.startsWith('MemAvailable') ||
            line.startsWith('MemFree')) {
          final parts = line.split(RegExp(r'\s+'));
          out[parts[0].replaceAll(':', '')] = '${parts[1]} kB';
        }
      }
      return out;
    } catch (e) {
      return {'error': '$e'};
    }
  }

  // ---- b. rotary ----
  void onScroll(String desc) {
    scrollEvents++;
    lastScroll = desc;
    notifyListeners();
  }

  void onNativeRotary(double delta) {
    nativeRotaryEvents++;
    nativeRotaryTotal += delta;
    notifyListeners();
  }

  void onKey(String desc) {
    keyEvents++;
    lastKey = desc;
    notifyListeners();
  }

  void resetRotary() {
    scrollEvents = 0;
    keyEvents = 0;
    nativeRotaryEvents = 0;
    nativeRotaryTotal = 0;
    lastScroll = '-';
    lastKey = '-';
    notifyListeners();
  }

  void saveRotary() {
    final received = scrollEvents + keyEvents + nativeRotaryEvents > 0;
    add(SpikeResult(
      name: 'rotary_input',
      status: received ? SpikeStatus.ok : SpikeStatus.fail,
      details: 'scroll=$scrollEvents key=$keyEvents native=$nativeRotaryEvents '
          '(sum ${nativeRotaryTotal.toStringAsFixed(1)}) last scroll: $lastScroll; '
          'last key: $lastKey',
      durationMs: 0,
      data: {
        'scrollEvents': scrollEvents,
        'keyEvents': keyEvents,
        'nativeRotaryEvents': nativeRotaryEvents,
        'nativeRotaryTotal': nativeRotaryTotal,
        'lastScroll': lastScroll,
        'lastKey': lastKey,
      },
    ));
  }

  // ---- c. BLE + Chameleon ----
  Future<void> bleScan() async {
    busy = true;
    _set('Requesting Bluetooth permissions...');
    final permResult = await runSpikeCheck('ble_permissions', () async {
      final res = await [Permission.bluetoothScan, Permission.bluetoothConnect]
          .request();
      final txt = res.entries.map((e) => '${e.key}: ${e.value.name}').join(', ');
      final granted = res.values.every((s) => s.isGranted);
      return granted ? SpikeOutcome.ok(txt) : SpikeOutcome.fail(txt);
    }, timeout: const Duration(seconds: 60));
    add(permResult);

    _set('Scanning...');
    final scan = await runSpikeCheck('ble_scan', () async {
      serial ??= BLESerial(log: Logger(level: Level.warning));
      found = await serial!.availableChameleons(false);
      final names = found.map((c) => '${chameleonDeviceName(c.device)}'
          '${c.dfu ? " (DFU)" : ""} ${c.port}');
      return found.isEmpty
          ? const SpikeOutcome.fail(
              'no Chameleon found (powered on? BLE on? not connected to a phone?)')
          : SpikeOutcome.ok('found ${found.length}: ${names.join(', ')}');
    }, timeout: const Duration(seconds: 20));
    busy = false;
    add(scan);
  }

  Future<void> bleConnectAndQuery(Chameleon target) async {
    busy = true;
    _set('Connecting...');
    final connect = await runSpikeCheck('ble_connect', () async {
      final sw = Stopwatch()..start();
      final ok = await serial!.connectSpecificDevice(target.port);
      if (!ok) {
        return const SpikeOutcome.fail('connectSpecificDevice returned false');
      }
      communicator = ChameleonCommunicator(Logger(level: Level.warning),
          port: serial as AbstractSerial);
      return SpikeOutcome.ok('connected in ${sw.elapsedMilliseconds} ms',
          {'connectMs': sw.elapsedMilliseconds});
    }, timeout: const Duration(seconds: 90));
    add(connect);
    if (connect.status != SpikeStatus.ok) {
      busy = false;
      notifyListeners();
      return;
    }

    final c = communicator!;
    await _step('chameleon_firmware', () async {
      final v = await c.getFirmwareVersion();
      return SpikeOutcome.ok(
          'version ${v.version} (0x${v.version.toRadixString(16)}) legacy=${v.legacyProtocol}');
    });
    await _step('chameleon_battery', () async {
      final b = await c.getBatteryCharge();
      return SpikeOutcome.ok('${b.percent}% ${b.voltage} mV');
    });
    await _step('chameleon_mode', () async {
      final reader = await c.isReaderDeviceMode();
      return SpikeOutcome.ok(reader ? 'reader' : 'emulator');
    });
    await _step('chameleon_slot', () async {
      return SpikeOutcome.ok('active slot ${await c.getActiveSlot()}');
    });
    await _step('chameleon_hf_scan', () async {
      final card = await c.scan14443aTag();
      return SpikeOutcome.ok(card == null
          ? 'returned cleanly, no card'
          : 'card uid ${bytesToHex(card.uid)} sak ${card.sak}');
    }, timeout: const Duration(seconds: 15));
    await _step('chameleon_latency_20', () async {
      final times = <int>[];
      for (var i = 0; i < 20; i++) {
        final sw = Stopwatch()..start();
        await c.getBatteryCharge();
        times.add(sw.elapsedMilliseconds);
      }
      times.sort();
      final avg = times.reduce((a, b) => a + b) / times.length;
      return SpikeOutcome.ok(
          '20 round trips: min ${times.first} avg ${avg.round()} '
          'p95 ${times[18]} max ${times.last} ms',
          {'minMs': times.first, 'avgMs': avg, 'maxMs': times.last, 'all': times});
    }, timeout: const Duration(seconds: 60));
    busy = false;
    _set('BLE checks done');
  }

  Future<void> _step(String name, Future<SpikeOutcome> Function() body,
      {Duration timeout = const Duration(seconds: 10)}) async {
    _set('Running $name...');
    add(await runSpikeCheck(name, body, timeout: timeout));
  }

  Future<void> bleDisconnect() async {
    try {
      await serial?.performDisconnect();
    } catch (_) {}
    communicator = null;
    _set('Disconnected');
  }

  Future<void> keepAliveTest({int seconds = 90, int intervalSeconds = 5}) async {
    final c = communicator;
    if (c == null) {
      add(const SpikeResult(
          name: 'ble_keepalive',
          status: SpikeStatus.skipped,
          details: 'not connected',
          durationMs: 0));
      return;
    }
    busy = true;
    try {
      await WakelockPlus.disable(); // let the screen sleep
    } catch (_) {}
    final total = seconds ~/ intervalSeconds;
    final sw = Stopwatch()..start();
    var okCount = 0;
    var maxGapMs = 0;
    var lastAt = sw.elapsedMilliseconds;
    final errors = <String>[];
    for (var i = 0; i < total; i++) {
      final now = sw.elapsedMilliseconds;
      if (i > 0 && now - lastAt > maxGapMs) maxGapMs = now - lastAt;
      lastAt = now;
      try {
        await c.getBatteryCharge().timeout(const Duration(seconds: 4));
        okCount++;
      } catch (e) {
        if (errors.length < 5) errors.add('t=${now ~/ 1000}s: $e');
      }
      keepAliveProgress = '$okCount/${i + 1} ok';
      notifyListeners();
      final wait = intervalSeconds * 1000 - (sw.elapsedMilliseconds - now);
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
    }
    busy = false;
    add(SpikeResult(
      name: 'ble_keepalive',
      status: okCount == total ? SpikeStatus.ok : SpikeStatus.fail,
      details: '$okCount/$total queries ok over ${sw.elapsed.inSeconds} s, '
          'max gap between queries $maxGapMs ms'
          '${errors.isEmpty ? "" : "; errors: ${errors.join(' | ')}"}',
      durationMs: sw.elapsedMilliseconds,
      data: {'ok': okCount, 'total': total, 'maxGapMs': maxGapMs},
    ));
    _set('Keep-alive finished');
  }

  // ---- d. native recovery ----
  Future<void> recoveryChecks() async {
    busy = true;
    final load = await runSpikeCheck('recovery_load', () async {
      final path = recovery.resolvePath();
      DynamicLibrary.open(path);
      return SpikeOutcome.ok('loaded $path');
    });
    add(load);
    if (load.status != SpikeStatus.ok) {
      for (final n in ['darkside', 'nested', 'static_encrypted_nested']) {
        add(SpikeResult(
            name: 'recovery_$n',
            status: SpikeStatus.skipped,
            details: 'library did not load',
            durationMs: 0));
      }
      busy = false;
      notifyListeners();
      return;
    }
    const to = Duration(seconds: 60);
    await _step('recovery_darkside', () async {
      final d = recovery.DarksideDart(uid: 2374329723, items: [
        recovery.DarksideItemDart(
            nt1: 913032415, ks1: 216745674933338888, par: 0, nr: 0, ar: 0),
        recovery.DarksideItemDart(
            nt1: 913032415, ks1: 1010230244403446283, par: 0, nr: 1, ar: 0),
      ]);
      final keys = await recovery.darkside(d);
      return _keyOutcome(keys, 0xFFFFFFFFFFFF);
    }, timeout: to);
    await _step('recovery_nested', () async {
      final keys = await recovery.nested(recovery.NestedDart(
          uid: 2374329723,
          distance: 613,
          nt0: 1999585272,
          nt0Enc: 3173333529,
          par0: 3,
          nt1: 128306861,
          nt1Enc: 2363514210,
          par1: 7));
      return _keyOutcome(keys, 0xFFFFFFFFFFFF);
    }, timeout: to);
    await _step('recovery_static_encrypted_nested', () async {
      final keys = await recovery.staticEncryptedNested(
          recovery.StaticEncryptedNestedDart(
              uid: 0x72000003,
              nt: 0x82d91e42,
              ntEnc: 0x98b90e04,
              ntParEnc: 1011));
      return _keyOutcome(keys, 0x55654483DA14);
    }, timeout: to);
    busy = false;
    _set('Recovery checks done (hardnested is separate)');
  }

  SpikeOutcome _keyOutcome(List<int> keys, int expected) => keys.contains(expected)
      ? SpikeOutcome.ok('found expected key among ${keys.length}',
          {'candidates': keys.length})
      : SpikeOutcome.fail('expected key missing among ${keys.length}');

  /// Run LAST: a native OOM kill cannot be caught, so persist first.
  Future<void> hardnestedCheck() async {
    busy = true;
    report.notes['memoryBeforeHardnested'] = _memInfo();
    await persistReport();
    try {
      _markerFile.writeAsStringSync(DateTime.now().toIso8601String());
    } catch (_) {}
    final r = await _run('recovery_hardnested', () async {
      final keys = await recovery.hardNested(
          recovery.HardNestedDart(nonces: hexToBytes(hardNestedNoncesHex)));
      report.notes['memoryAfterHardnested'] = _memInfo();
      return _keyOutcome(keys, 0xFBF225DC5D58);
    }, timeout: const Duration(seconds: 120));
    if (r.status != SpikeStatus.fail || !r.details.startsWith('timeout')) {
      try {
        _markerFile.deleteSync();
      } catch (_) {}
    }
    await persistReport();
  }

  // ---- e. storage ----
  Future<void> storageChecks() => _run('storage_timing', () async {
        final sw = Stopwatch()..start();
        final prefs = await SharedPreferences.getInstance();
        final getMs = sw.elapsedMilliseconds;
        sw.reset();
        await prefs.reload();
        final reloadEmptyMs = sw.elapsedMilliseconds;
        final big = '{"k":"${List.filled(5 * 1024 * 1024, 'a').join()}"}';
        sw.reset();
        await prefs.setString('wear_spike_throwaway', big);
        final writeMs = sw.elapsedMilliseconds;
        sw.reset();
        await prefs.reload();
        final reload5Ms = sw.elapsedMilliseconds;
        await prefs.remove('wear_spike_throwaway');
        return SpikeOutcome.ok(
            'getInstance $getMs ms, reload(empty) $reloadEmptyMs ms, '
            'write 5MB $writeMs ms, reload(5MB) $reload5Ms ms',
            {
              'getInstanceMs': getMs,
              'reloadBaselineMs': reloadEmptyMs,
              'write5MbMs': writeMs,
              'reload5MbMs': reload5Ms,
            });
      }, timeout: const Duration(seconds: 60));

  // ---- f. network ----
  Uri _healthUri() {
    final u = Uri.parse(reportUrl);
    return u.replace(path: '/health');
  }

  Future<void> networkCheck() => _run('network', () async {
        final sw = Stopwatch()..start();
        final resp =
            await http.get(_healthUri()).timeout(const Duration(seconds: 8));
        return resp.statusCode == 200
            ? SpikeOutcome.ok(
                'GET ${_healthUri()} -> ${resp.statusCode} "${resp.body.trim()}" in ${sw.elapsedMilliseconds} ms')
            : SpikeOutcome.fail('HTTP ${resp.statusCode}');
      }, timeout: const Duration(seconds: 10));

  // ---- report ----
  Future<void> persistReport() async {
    try {
      report.notes['rotaryScrollEvents'] = scrollEvents;
      report.notes['rotaryKeyEvents'] = keyEvents;
      await _reportFile.writeAsString(report.toJsonString());
    } catch (_) {}
  }

  /// Copies live counters into the report notes; call before exporting.
  void finalizeReportNotes() {
    report.notes['rotaryScrollEvents'] = scrollEvents;
    report.notes['rotaryKeyEvents'] = keyEvents;
    report.notes['rotaryNativeEvents'] = nativeRotaryEvents;
    if (previousHardnestedUnfinished) {
      report.notes['previousRunDidNotFinishHardnested'] = true;
    }
  }

  Future<void> sendReport() => _run('report_send', () async {
        finalizeReportNotes();
        final body = report.toJsonString();
        await _reportFile.writeAsString(body);
        final resp = await http
            .post(Uri.parse(reportUrl),
                headers: {'content-type': 'application/json'},
                body: utf8.encode(body))
            .timeout(const Duration(seconds: 20));
        return resp.statusCode >= 200 && resp.statusCode < 300
            ? SpikeOutcome.ok(
                'POST ${resp.statusCode}, ${body.length} bytes; saved to ${_reportFile.path}')
            : SpikeOutcome.fail(
                'HTTP ${resp.statusCode} ${resp.body}; saved to ${_reportFile.path}');
      }, timeout: const Duration(seconds: 25));
}
