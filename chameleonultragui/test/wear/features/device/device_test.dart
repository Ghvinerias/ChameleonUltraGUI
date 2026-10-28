import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/wear/connection/ui/connect_screen.dart';
import 'package:chameleonultragui/wear/connection/wear_connection.dart';
import 'package:chameleonultragui/wear/features/device/ble_page.dart';
import 'package:chameleonultragui/wear/features/device/device_entry.dart';
import 'package:chameleonultragui/wear/features/device/device_page.dart';
import 'package:chameleonultragui/wear/features/device/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wear_test_services.dart';
import 'device_fake.dart';

Future<void> go(WidgetTester t) => t.pump(const Duration(milliseconds: 600));

/// The list builds lazily on a 206 dp screen: go to the top, then scroll
/// down until [f] is built and visible.
Future<void> reveal(WidgetTester t, Finder f) async {
  final list = find.byType(Scrollable).last;
  await t.drag(list, const Offset(0, 5000));
  await t.pumpAndSettle();
  await t.scrollUntilVisible(f, 60, scrollable: list);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<Finder> keyed(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await reveal(t, f);
  return f;
}

Future<void> shows(WidgetTester t, String text) async {
  final f = find.text(text);
  await reveal(t, f);
  expect(f, findsOneWidget);
}

/// Absent from the whole list (top to bottom).
Future<void> gone(WidgetTester t, String text) async {
  final list = find.byType(Scrollable).last;
  await t.drag(list, const Offset(0, 5000));
  await t.pump();
  for (var i = 0; i < 15; i++) {
    expect(find.text(text), findsNothing);
    await t.drag(list, const Offset(0, -120));
    await t.pump();
  }
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  await reveal(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await reveal(t, f);
  await t.tap(f);
  await t.pump();
}

Future<DeviceFake> open(
  WidgetTester t, {
  Widget page = const DevicePage(),
  DeviceFake? fake,
  double scale = 1.0,
}) async {
  final f = fake ?? DeviceFake();
  final rig = await createWearRig(fake: f);
  await rig.pump(t, page, textScale: scale);
  await t.pumpAndSettle();
  return f;
}

void main() {
  group('info', () {
    testWidgets('renders info with four commands', (t) async {
      final fake = DeviceFake()
        ..activeSlot = 5
        ..readerMode = true;
      await open(t, fake: fake);
      expect(fake.cmds, [
        'getFirmwareVersion',
        'getBatteryCharge',
        'isReaderDeviceMode',
        'getActiveSlot',
      ]);
      await shows(t, 'Ultra');
      await shows(t, 'AA:BB:CC:DD:EE:FF');
      await shows(t, 'Connected');
      await shows(t, '2.2');
      await shows(t, '65% · 3.94 V');
      await shows(t, 'Reader');
      await shows(t, '6');
      expect(fake.writes, isEmpty);
    });

    testWidgets('entry builds the device page', (t) async {
      await open(t, page: Builder(builder: deviceEntry));
      expect(find.byType(DevicePage), findsOneWidget);
    });

    testWidgets('refresh re-reads, failure shows message and retry works', (
      t,
    ) async {
      final fake = DeviceFake();
      await open(t, fake: fake);
      fake.batteryPercent = 40;
      await tapText(t, 'Refresh');
      await shows(t, '40% · 3.94 V');

      fake.failing.add('getBatteryCharge');
      await tapText(t, 'Refresh');
      await shows(t, 'Could not read the device');
      // last known values stay visible
      await shows(t, '40% · 3.94 V');

      fake.failing.clear();
      fake.batteryPercent = 30;
      await tapText(t, 'Refresh');
      await gone(t, 'Could not read the device');
      await shows(t, '30% · 3.94 V');
    });

    testWidgets('first read failure shows an error', (t) async {
      final fake = DeviceFake()..failing.add('getFirmwareVersion');
      await open(t, fake: fake);
      await shows(t, 'Could not read the device');
      await shows(t, 'Refresh');
    });
  });

  group('connection', () {
    testWidgets('disconnected shows the connect screen', (t) async {
      final rig = await createWearRig(connected: false);
      await rig.pump(t, const DevicePage());
      await go(t);
      expect(find.byType(ConnectScreen), findsOneWidget);
      await gone(t, 'Refresh');
    });

    testWidgets('disconnect asks first, cancel keeps the link', (t) async {
      final fake = DeviceFake();
      final rig = await createWearRig(fake: fake);
      await rig.pump(t, const DevicePage());
      await t.pumpAndSettle();
      await tapText(t, 'Disconnect');
      await shows(t, 'Disconnect?');
      await tapText(t, 'Cancel');
      expect(rig.connection.isConnected, isTrue);
    });

    testWidgets('disconnect confirmed ends the link, shows connect screen', (
      t,
    ) async {
      final rig = await createWearRig();
      await rig.pump(t, const DevicePage());
      await t.pumpAndSettle();
      final remembered = rig.connection.lastDeviceId;
      expect(remembered, isNotNull);
      await tapText(t, 'Disconnect');
      await tapText(t, 'Disconnect'); // confirm button
      await go(t);
      expect(rig.connection.isConnected, isFalse);
      expect(rig.connection.state, isNot(WearConnectionState.connected));
      expect(rig.connection.lastDeviceId, remembered, reason: 'not forgotten');
      expect(find.byType(ConnectScreen), findsOneWidget);
    });

    testWidgets('forget needs confirmation and clears the remembered id', (
      t,
    ) async {
      final rig = await createWearRig();
      await rig.pump(t, const DevicePage());
      await t.pumpAndSettle();
      await tapText(t, 'Forget this device');
      await shows(t, 'Forget device?');
      await tapText(t, 'Cancel');
      expect(rig.connection.isConnected, isTrue);
      expect(rig.connection.lastDeviceId, isNotNull);

      await tapText(t, 'Forget this device');
      await tapText(t, 'Forget this device'); // confirm button
      await go(t);
      expect(rig.connection.isConnected, isFalse);
      expect(rig.connection.lastDeviceId, isNull);
      expect(find.byType(ConnectScreen), findsOneWidget);
    });
  });

  group('settings', () {
    Future<DeviceFake> openSettings(WidgetTester t, {DeviceFake? fake}) =>
        open(t, page: const DeviceSettingsPage(), fake: fake);

    testWidgets('reads once, no writes', (t) async {
      final fake = await openSettings(t);
      expect(fake.cmds, [
        'getDeviceSettings',
        'getDeviceCapabilities',
        'getLongPressThreshold',
      ]);
      await shows(t, 'Full');
      await shows(t, '1000 ms');
      await shows(t, '20 s');
    });

    testWidgets('opened from the device page', (t) async {
      await open(t);
      await tapText(t, 'Settings');
      expect(find.byType(DeviceSettingsPage), findsOneWidget);
      await shows(t, 'Full');
    });

    testWidgets('animation: writes set then save, shows saved', (t) async {
      final fake = await openSettings(t);
      await tapText(t, 'Animation');
      await tapText(t, 'None');
      expect(fake.writes, ['setAnimationMode(2)', 'saveSettings']);
      expect(fake.animation, AnimationSetting.none);
      await shows(t, 'None · Saved');
    });

    testWidgets('animation: failed write reverts and says so', (t) async {
      final fake = DeviceFake()..failing.add('setAnimationMode');
      await openSettings(t, fake: fake);
      await tapText(t, 'Animation');
      await tapText(t, 'None');
      await shows(t, 'Not saved, reverted: Full');
      expect(fake.writes, ['setAnimationMode(2)']);
    });

    testWidgets('failed saveSettings also reverts', (t) async {
      final fake = DeviceFake()..failing.add('saveSettings');
      await openSettings(t, fake: fake);
      await tapText(t, 'Animation');
      await tapText(t, 'Mini');
      await shows(t, 'Not saved, reverted: Full');
    });

    testWidgets('picking the current value writes nothing', (t) async {
      final fake = await openSettings(t);
      await tapText(t, 'Animation');
      await tapText(t, 'Full');
      expect(fake.writes, isEmpty);
    });

    final buttonCases = <(String, String, String, String)>[
      (
        'Button A, short press',
        'Disabled',
        'setButtonConfig(a,0)',
        'Cycle forward',
      ),
      (
        'Button B, short press',
        'Clone UID',
        'setButtonConfig(b,3)',
        'Cycle backward',
      ),
      (
        'Button A, long press',
        'Charge status',
        'setLongButtonConfig(a,4)',
        'Disabled',
      ),
      (
        'Button B, long press',
        'Cycle forward',
        'setLongButtonConfig(b,1)',
        'Clone UID',
      ),
    ];
    for (final (label, pick, command, before) in buttonCases) {
      testWidgets('$label -> $pick', (t) async {
        final fake = await openSettings(t);
        await tapText(t, label);
        await tapText(t, pick);
        expect(fake.writes, [command, 'saveSettings']);
        await shows(t, '$pick · Saved');
      });
      testWidgets('$label failure reverts to $before', (t) async {
        final fake = DeviceFake()..failing.add(command.split('(').first);
        await openSettings(t, fake: fake);
        await tapText(t, label);
        await tapText(t, pick);
        await shows(t, 'Not saved, reverted: $before');
      });
    }

    testWidgets('long press time stepper writes once on Save', (t) async {
      final fake = await openSettings(t);
      await tapText(t, 'Long press time');
      await tapKey(t, 'stepper-plus');
      await tapKey(t, 'stepper-plus');
      await shows(t, '1100 ms');
      expect(fake.writes, isEmpty, reason: 'nothing written while stepping');
      await tapText(t, 'Save');
      expect(fake.writes, ['setLongPressThreshold(1100)', 'saveSettings']);
      await shows(t, '1100 ms · Saved');
    });

    testWidgets('long press time clamps to 200..1800', (t) async {
      final fake = DeviceFake()..threshold = 220;
      await openSettings(t, fake: fake);
      await tapText(t, 'Long press time');
      await tapKey(t, 'stepper-minus');
      await shows(t, '200 ms');
      await tapKey(t, 'stepper-minus');
      await shows(t, '200 ms');
      final minus = t.widget<IconButton>(
        find.byKey(const ValueKey('stepper-minus')),
      );
      expect(minus.onPressed, isNull);
    });

    testWidgets('long press time failure reverts', (t) async {
      final fake = DeviceFake()..failing.add('setLongPressThreshold');
      await openSettings(t, fake: fake);
      await tapText(t, 'Long press time');
      await tapKey(t, 'stepper-plus');
      await tapText(t, 'Save');
      await shows(t, 'Not saved, reverted: 1000 ms');
    });

    testWidgets('wake time stepper (5..60 s)', (t) async {
      final fake = await openSettings(t);
      await tapText(t, 'Wake time after button press');
      await tapKey(t, 'stepper-minus');
      await shows(t, '15 s');
      await tapText(t, 'Save');
      expect(fake.writes, ['setSleepTimeout(15)', 'saveSettings']);
    });

    testWidgets('wake time failure reverts', (t) async {
      final fake = DeviceFake()..failing.add('setSleepTimeout');
      await openSettings(t, fake: fake);
      await tapText(t, 'Wake time after button press');
      await tapKey(t, 'stepper-plus');
      await tapText(t, 'Save');
      await shows(t, 'Not saved, reverted: 20 s');
    });

    testWidgets('threshold and wake hidden on old firmware', (t) async {
      final fake = DeviceFake(withThreshold: false, withWake: false);
      await openSettings(t, fake: fake);
      await gone(t, 'Long press time');
      await gone(t, 'Wake time after button press');
      expect(fake.cmds, ['getDeviceSettings', 'getDeviceCapabilities']);
    });

    testWidgets('read failure offers retry', (t) async {
      final fake = DeviceFake()..failing.add('getDeviceSettings');
      await openSettings(t, fake: fake);
      await shows(t, 'Could not read the device');
      fake.failing.clear();
      await tapText(t, 'Retry');
      await shows(t, 'Animation');
    });
  });

  group('bluetooth', () {
    Future<DeviceFake> openBle(WidgetTester t, {DeviceFake? fake}) =>
        open(t, page: const DeviceBlePage(), fake: fake);

    testWidgets('reads settings once', (t) async {
      final fake = await openBle(t);
      expect(fake.cmds, ['getDeviceSettings']);
      await shows(t, 'Enabled');
      await shows(t, 'Change pairing key');
    });

    testWidgets('pairing toggle writes, hides key actions when off', (t) async {
      final fake = await openBle(t);
      await tapText(t, 'BLE pairing');
      expect(fake.writes, ['setBLEPairEnabled(false)', 'saveSettings']);
      await shows(t, 'Disabled · Saved');
      await gone(t, 'Change pairing key');
      await gone(t, 'Clear bonded devices');
    });

    testWidgets('pairing toggle failure reverts', (t) async {
      final fake = DeviceFake()..failing.add('setBLEPairEnabled');
      await openBle(t, fake: fake);
      await tapText(t, 'BLE pairing');
      await shows(t, 'Not saved, reverted: Enabled');
      await shows(t, 'Change pairing key');
    });

    testWidgets('key change is gated by a confirm dialog', (t) async {
      final fake = await openBle(t);
      await tapText(t, 'Change pairing key');
      await shows(t, 'Change PIN?');
      await tapText(t, 'Cancel');
      await gone(t, 'New PIN');
      expect(fake.writes, isEmpty);
    });

    testWidgets('PIN must be 6 digits, then it is written', (t) async {
      final fake = await openBle(t);
      await tapText(t, 'Change pairing key');
      await tapText(t, 'Continue');
      await shows(t, 'New PIN');

      for (final d in '65432'.split('')) {
        await tapKey(t, 'pin-$d');
      }
      await tapText(t, 'Set PIN');
      expect(await keyed(t, 'pin-error'), findsOneWidget);
      await shows(t, 'PIN must be 6 digits');
      expect(fake.writes, isEmpty);

      await tapKey(t, 'pin-1');
      await tapKey(t, 'pin-9'); // seventh digit is ignored
      expect(t.widget<Text>(await keyed(t, 'pin-display')).data, '6 5 4 3 2 1');
      await tapText(t, 'Set PIN');
      await t.pumpAndSettle();
      expect(fake.writes, ['setBLEConnectKey(654321)', 'saveSettings']);
      await shows(t, 'PIN changed');
    });

    testWidgets('backspace edits the PIN', (t) async {
      await openBle(t);
      await tapText(t, 'Change pairing key');
      await tapText(t, 'Continue');
      await tapKey(t, 'pin-1');
      await tapKey(t, 'pin-2');
      await tapKey(t, 'pin-back');
      expect(t.widget<Text>(await keyed(t, 'pin-display')).data, '1 – – – – –');
    });

    testWidgets('PIN write failure is reported, key not changed', (t) async {
      final fake = DeviceFake()..failing.add('setBLEConnectKey');
      await openBle(t, fake: fake);
      await tapText(t, 'Change pairing key');
      await tapText(t, 'Continue');
      for (final d in '111111'.split('')) {
        await tapKey(t, 'pin-$d');
      }
      await tapText(t, 'Set PIN');
      await shows(t, 'Not saved, reverted');
      expect(fake.key, '123456');
    });

    testWidgets('clear bonds: cancel does nothing', (t) async {
      final fake = await openBle(t);
      await tapText(t, 'Clear bonded devices');
      await shows(t, 'Clear bonds?');
      await tapText(t, 'Cancel');
      expect(fake.cmds, ['getDeviceSettings']);
    });

    testWidgets('clear bonds: confirm clears and disconnects', (t) async {
      final fake = DeviceFake();
      final rig = await createWearRig(fake: fake);
      await rig.pump(t, const DeviceBlePage());
      await t.pumpAndSettle();
      await tapText(t, 'Clear bonded devices');
      await tapText(t, 'Clear bonded devices'); // confirm button
      await go(t);
      expect(fake.cmds, contains('clearBLEBoundedDevices'));
      expect(rig.connection.isConnected, isFalse);
      expect(find.byType(ConnectScreen), findsOneWidget);
    });

    testWidgets('clear bonds failure stays connected and says so', (t) async {
      final fake = DeviceFake()..failing.add('clearBLEBoundedDevices');
      final rig = await createWearRig(fake: fake);
      await rig.pump(t, const DeviceBlePage());
      await t.pumpAndSettle();
      await tapText(t, 'Clear bonded devices');
      await tapText(t, 'Clear bonded devices');
      await shows(t, 'Could not clear bonds');
      expect(rig.connection.isConnected, isTrue);
    });
  });

  group('layout at 206 dp', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow, scale $scale', (t) async {
        final fake = DeviceFake();
        final rig = await createWearRig(fake: fake);
        await rig.pump(t, const DevicePage(), textScale: scale);
        await t.pumpAndSettle();

        Future<void> sweep() async {
          expect(t.takeException(), isNull);
          final list = find.byType(Scrollable).last;
          for (var i = 0; i < 12; i++) {
            await t.drag(list, const Offset(0, -150));
            await t.pump();
            expect(t.takeException(), isNull);
          }
        }

        await sweep();
        await tapText(t, 'Settings');
        await sweep();
        await tapText(t, 'Long press time');
        await sweep();
        t.state<NavigatorState>(find.byType(Navigator)).pop();
        await t.pumpAndSettle();
        t.state<NavigatorState>(find.byType(Navigator)).pop();
        await t.pumpAndSettle();
        await tapText(t, 'Bluetooth & security');
        await sweep();
        await tapText(t, 'Change pairing key');
        await sweep();
        await tapText(t, 'Continue');
        await sweep();
      });
    }
  });
}
