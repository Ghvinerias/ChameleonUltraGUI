import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/wear/connection/wear_connection.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/fake_chameleon_communicator.dart';
import '../kit/wear_test_harness.dart';

/// A BLE-less serial that "finds" one Ultra and connects instantly.
class _AutoSerial extends AbstractSerial {
  _AutoSerial() : super(log: Logger(level: Level.off));

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [
    const Chameleon(
      port: 'AA:BB:CC:DD:EE:FF',
      device: ChameleonDevice.ultra,
      type: ConnectionType.ble,
      dfu: false,
    ),
  ];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
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

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;
}

class _AllowPerms implements WearPermissions {
  @override
  Future<bool> isGranted() async => true;
  @override
  Future<WearPermissionResult> request() async => WearPermissionResult.granted;
  @override
  Future<void> openSettings() async {}
}

/// Everything a watch feature test needs: real services over fakes.
class WearTestRig {
  WearTestRig(this.services, this.fake, this.connection, this.prefs);

  final WearServices services;

  /// The scripted Chameleon behind the connection (cards, slots, call log).
  final FakeChameleonCommunicator fake;
  final WearConnection connection;
  final SharedPreferencesProvider prefs;

  /// Wraps [screen] like the real app: services scope + watch MaterialApp.
  Widget host(Widget screen) =>
      WearServicesScope(services: services, child: wearMaterial(screen));

  /// Pumps [screen] on a 438x438 px / DPR 2.125 round surface.
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    double textScale = 1.0,
  }) async {
    mockRotaryChannel();
    await pumpWear(tester, host(screen), textScale: textScale);
  }
}

/// Builds a rig. With [connected] (default) the fake Chameleon is already
/// connected; otherwise the connection is idle (to test the gate).
///
/// [prefsValues] seeds SharedPreferences (cards, dictionaries as the phone app
/// stores them). Call inside a test or `setUp` after
/// `TestWidgetsFlutterBinding.ensureInitialized()`.
Future<WearTestRig> createWearRig({
  FakeChameleonCommunicator? fake,
  Map<String, Object> prefsValues = const {},
  bool connected = true,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(Map.of(prefsValues));
  final device = fake ?? FakeChameleonCommunicator();
  final prefs = SharedPreferencesProvider();
  await prefs.load();
  final connection = WearConnection(
    serialFactory: (_) => _AutoSerial(),
    communicatorFactory: (_, _) => device,
    permissions: _AllowPerms(),
    log: Logger(level: Level.off),
  );
  if (connected) {
    final found = await connection.scan();
    await connection.connect(found.first);
  }
  return WearTestRig(
    WearServices(prefs: prefs, connection: connection),
    device,
    connection,
    prefs,
  );
}
