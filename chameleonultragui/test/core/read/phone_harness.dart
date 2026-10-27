import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/fake_chameleon_communicator.dart';

/// Serial stand-in: the fake communicator never touches it, only
/// `connectionType` / `device` are read by the phone code.
class FakeSerial extends AbstractSerial {
  FakeSerial({
    ConnectionType type = ConnectionType.ble,
    ChameleonDevice chameleon = ChameleonDevice.ultra,
  }) : super(log: Logger(level: Level.off)) {
    connectionType = type;
    device = chameleon;
    connected = true;
  }

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => false;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;
}

/// Mounts [child] inside a MaterialApp with localizations and a
/// `ChameleonGUIState` wired to [communicator].
Future<ChameleonGUIState> pumpPhoneApp(
  WidgetTester tester,
  FakeChameleonCommunicator communicator,
  Widget child, {
  ConnectionType connectionType = ConnectionType.ble,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = SharedPreferencesProvider();
  await prefs.load();
  final appState = ChameleonGUIState(prefs)
    ..log = Logger(level: Level.off)
    ..connector = FakeSerial(type: connectionType)
    ..communicator = communicator;
  await tester.pumpWidget(
    ChangeNotifierProvider<ChameleonGUIState>.value(
      value: appState,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  return appState;
}

/// Strips the per-key detail from a call log so assertions stay readable:
/// collapses runs of identical entries into `entry xN`.
List<String> compactLog(List<String> log) {
  final out = <String>[];
  var i = 0;
  while (i < log.length) {
    var j = i;
    while (j < log.length && log[j] == log[i]) {
      j++;
    }
    out.add(j - i > 1 ? '${log[i]} x${j - i}' : log[i]);
    i = j;
  }
  return out;
}
