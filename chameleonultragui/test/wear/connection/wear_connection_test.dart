import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/wear/connection/wear_connection.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/fake_chameleon_communicator.dart';

class FakeSerial extends AbstractSerial {
  List<Chameleon> visible = [];
  int connectCalls = 0;

  /// Results consumed per connect attempt; empty => success.
  final List<bool> connectScript = [];
  bool connectHangs = false;

  FakeSerial() : super(log: Logger(level: Level.off));

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    await performDisconnect();
    return visible;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    connectCalls++;
    await performDisconnect();
    final ok = connectScript.isEmpty ? true : connectScript.removeAt(0);
    if (!ok) return false;
    connected = true;
    portName = devicePort;
    activeDevicePort = devicePort;
    return true;
  }

  @override
  Future<bool> performDisconnect() async {
    final had = connected;
    resetConnectionState();
    if (had) notifyConnectionStateChanged();
    return had;
  }

  /// Simulates the watch/device dropping the link.
  void drop() {
    connected = false;
    notifyConnectionStateChanged();
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;
}

class FakePerms implements WearPermissions {
  WearPermissionResult next = WearPermissionResult.granted;
  bool granted = false;
  int requests = 0;
  @override
  Future<bool> isGranted() async => granted;
  @override
  Future<WearPermissionResult> request() async {
    requests++;
    if (next == WearPermissionResult.granted) granted = true;
    return next;
  }

  @override
  Future<void> openSettings() async {}
}

class BatteryFake extends FakeChameleonCommunicator {
  bool alive = true;
  int queries = 0;
  @override
  Future<BatteryCharge> getBatteryCharge() async {
    queries++;
    if (!alive) return Completer<BatteryCharge>().future; // hangs
    return BatteryCharge(voltage: 4000, percent: 80);
  }
}

Chameleon ultra(String id) => Chameleon(
  port: id,
  device: ChameleonDevice.ultra,
  type: ConnectionType.ble,
  dfu: false,
);
Chameleon dfu(String id) => Chameleon(
  port: id,
  device: ChameleonDevice.lite,
  type: ConnectionType.ble,
  dfu: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSerial serial;
  late FakePerms perms;
  late List<BatteryFake> comms;
  late WearConnection conn;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    serial = FakeSerial();
    perms = FakePerms();
    comms = [];
    conn = WearConnection(
      serialFactory: (_) => serial,
      communicatorFactory: (_, _) {
        final c = BatteryFake();
        comms.add(c);
        return c;
      },
      permissions: perms,
      log: Logger(level: Level.off),
    );
  });

  test('nothing happens at construction', () {
    expect(conn.state, WearConnectionState.idle);
    expect(conn.communicator, isNull);
    expect(serial.connectCalls, 0);
  });

  group('permissions', () {
    test('denied -> permissionNeeded, no scan', () async {
      perms.next = WearPermissionResult.denied;
      expect(await conn.scan(), isEmpty);
      expect(conn.state, WearConnectionState.permissionNeeded);
      expect(conn.lastError, WearConnectionError.permissionDenied);
    });

    test('permanently denied is reported', () async {
      perms.next = WearPermissionResult.permanentlyDenied;
      expect(await conn.ensurePermissions(), isFalse);
      expect(conn.lastError, WearConnectionError.permissionPermanentlyDenied);
    });

    test('granted later recovers', () async {
      perms.next = WearPermissionResult.denied;
      await conn.scan();
      perms.next = WearPermissionResult.granted;
      serial.visible = [ultra('AA:BB:CC:DD:EE:01')];
      await conn.scan();
      expect(conn.state, WearConnectionState.devicesFound);
    });
  });

  group('scan', () {
    test('0 devices', () async {
      await conn.scan();
      expect(conn.state, WearConnectionState.idle);
      expect(conn.lastError, WearConnectionError.noDeviceFound);
      expect(conn.devices, isEmpty);
    });

    test('1 device', () async {
      serial.visible = [ultra('AA:BB:CC:DD:EE:01')];
      final r = await conn.scan();
      expect(r.length, 1);
      expect(r.single.isUltra, isTrue);
      expect(conn.state, WearConnectionState.devicesFound);
    });

    test('2 devices, DFU separated', () async {
      serial.visible = [
        ultra('AA:BB:CC:DD:EE:01'),
        ultra('AA:BB:CC:DD:EE:02'),
        dfu('AA:BB:CC:DD:EE:03'),
      ];
      await conn.scan();
      expect(conn.devices.length, 2);
      expect(conn.dfuDevices.length, 1);
      expect(conn.dfuDevices.single.dfu, isTrue);
      expect(await conn.connect(conn.dfuDevices.single), isFalse);
      expect(conn.lastError, WearConnectionError.dfuDevice);
    });
  });

  group('connect', () {
    test('success', () async {
      serial.visible = [ultra('AA:01')];
      await conn.scan();
      expect(await conn.connect(conn.devices.single), isTrue);
      expect(conn.state, WearConnectionState.connected);
      expect(conn.communicator, isNotNull);
      expect(conn.lastDeviceId, 'AA:01');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(WearConnection.lastDevicePrefKey), 'AA:01');
    });

    test('failure', () async {
      serial.visible = [ultra('AA:01')];
      serial.connectScript.add(false);
      await conn.scan();
      expect(await conn.connect(conn.devices.single), isFalse);
      expect(conn.state, WearConnectionState.failed);
      expect(conn.lastError, WearConnectionError.connectFailed);
      expect(conn.communicator, isNull);
    });

    test('scan is refused while connected', () async {
      serial.visible = [ultra('AA:01')];
      await conn.scan();
      await conn.connect(conn.devices.single);
      await conn.scan();
      expect(conn.state, WearConnectionState.connected);
    });
  });

  group('reconnect', () {
    Future<void> connected(FakeSerial s) async {
      s.visible = [ultra('AA:01')];
      await conn.scan();
      await conn.connect(conn.devices.single);
    }

    test('drop -> backoff retries -> success', () {
      fakeAsync((async) {
        connected(serial);
        async.flushMicrotasks();
        expect(conn.isConnected, isTrue);

        serial.connectScript.addAll([false, false]); // 3rd attempt works
        final before = serial.connectCalls;
        serial.drop();
        async.flushMicrotasks();
        expect(conn.state, WearConnectionState.reconnecting);
        expect(conn.communicator, isNull);

        async.elapse(const Duration(milliseconds: 999));
        expect(serial.connectCalls, before);
        async.elapse(const Duration(milliseconds: 2));
        expect(serial.connectCalls, before + 1); // 1 s
        async.elapse(const Duration(seconds: 2));
        expect(serial.connectCalls, before + 2); // +2 s
        expect(conn.state, WearConnectionState.reconnecting);
        async.elapse(const Duration(seconds: 4));
        expect(serial.connectCalls, before + 3); // +4 s
        async.flushMicrotasks();
        expect(conn.state, WearConnectionState.connected);
        expect(conn.communicator, isNotNull);
        expect(comms.length, 2);
      });
    });

    test('drop -> give up -> failed', () {
      fakeAsync((async) {
        connected(serial);
        async.flushMicrotasks();
        serial.connectScript.addAll(List.filled(20, false));
        final before = serial.connectCalls;
        serial.drop();
        async.elapse(const Duration(minutes: 5));
        expect(serial.connectCalls - before, conn.policy.maxReconnectAttempts);
        expect(conn.state, WearConnectionState.failed);
        expect(conn.lastError, WearConnectionError.connectionLost);
        expect(conn.communicator, isNull);
      });
    });

    test('backoff is capped', () {
      const p = WearConnectionPolicy();
      expect(p.backoffFor(0), const Duration(seconds: 1));
      expect(p.backoffFor(2), const Duration(seconds: 4));
      expect(p.backoffFor(5), const Duration(seconds: 30));
      expect(p.backoffFor(20), const Duration(seconds: 30));
    });

    test('manual disconnect during reconnect cancels the loop', () {
      fakeAsync((async) {
        connected(serial);
        async.flushMicrotasks();
        serial.connectScript.addAll(List.filled(20, false));
        serial.drop();
        async.elapse(const Duration(milliseconds: 1500));
        conn.disconnect();
        final calls = serial.connectCalls;
        async.elapse(const Duration(minutes: 5));
        expect(serial.connectCalls, calls);
        expect(conn.state, WearConnectionState.idle);
      });
    });

    test('resume with dead link starts reconnect', () {
      fakeAsync((async) {
        connected(serial);
        async.flushMicrotasks();
        comms.last.alive = false;
        conn.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 5));
        // liveness timed out, link torn down, reconnect succeeded
        expect(conn.state, WearConnectionState.connected);
        expect(comms.length, 2);
      });
    });

    test('resume with healthy link does nothing', () {
      fakeAsync((async) {
        connected(serial);
        async.flushMicrotasks();
        final calls = serial.connectCalls;
        conn.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(comms.single.queries, 1);
        expect(serial.connectCalls, calls);
        expect(conn.isConnected, isTrue);
      });
    });

    test('resume while failed(connectionLost) retries', () {
      fakeAsync((async) {
        connected(serial);
        async.flushMicrotasks();
        serial.connectScript.addAll(List.filled(6, false));
        serial.drop();
        async.elapse(const Duration(minutes: 5));
        expect(conn.state, WearConnectionState.failed);
        conn.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 2));
        expect(conn.isConnected, isTrue);
      });
    });
  });

  group('manual disconnect + auto-connect', () {
    test('auto-connects to remembered device', () async {
      SharedPreferences.setMockInitialValues({
        WearConnection.lastDevicePrefKey: 'AA:02',
      });
      serial.visible = [ultra('AA:01'), ultra('AA:02')];
      expect(await conn.autoConnect(), isTrue);
      expect(conn.activeDevice!.id, 'AA:02');
    });

    test('remembered device absent -> stays on list', () async {
      SharedPreferences.setMockInitialValues({
        WearConnection.lastDevicePrefKey: 'AA:99',
      });
      serial.visible = [ultra('AA:01')];
      expect(await conn.autoConnect(), isFalse);
      expect(conn.state, WearConnectionState.devicesFound);
    });

    test('manual disconnect suppresses until device disappears', () async {
      serial.visible = [ultra('AA:01')];
      await conn.scan();
      await conn.connect(conn.devices.single);
      await conn.disconnect();
      expect(conn.state, WearConnectionState.idle);
      expect(conn.communicator, isNull);
      expect(conn.isAutoReconnectSuppressed('AA:01'), isTrue);

      expect(await conn.autoConnect(), isFalse); // still visible
      expect(conn.isConnected, isFalse);

      serial.visible = []; // disappears
      await conn.scan();
      expect(conn.isAutoReconnectSuppressed('AA:01'), isFalse);

      serial.visible = [ultra('AA:01')];
      expect(await conn.autoConnect(), isTrue);
    });

    test('non-manual disconnect does not suppress', () async {
      serial.visible = [ultra('AA:01')];
      await conn.scan();
      await conn.connect(conn.devices.single);
      await conn.disconnect(manual: false);
      expect(conn.isAutoReconnectSuppressed('AA:01'), isFalse);
      expect(await conn.autoConnect(), isTrue);
    });

    test('explicit connect clears suppression', () async {
      serial.visible = [ultra('AA:01')];
      await conn.scan();
      await conn.connect(conn.devices.single);
      await conn.disconnect();
      await conn.scan();
      await conn.connect(conn.devices.single);
      expect(conn.isAutoReconnectSuppressed('AA:01'), isFalse);
    });
  });

  test('isAlive false when not connected, true when answering', () async {
    expect(await conn.isAlive(), isFalse);
    serial.visible = [ultra('AA:01')];
    await conn.scan();
    await conn.connect(conn.devices.single);
    expect(await conn.isAlive(), isTrue);
  });
}
