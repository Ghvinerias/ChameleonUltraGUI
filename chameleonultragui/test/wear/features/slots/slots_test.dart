import 'dart:math' as math;

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/wear/connection/ui/connect_screen.dart';
import 'package:chameleonultragui/wear/features/slots/slot_detail_page.dart';
import 'package:chameleonultragui/wear/features/slots/slot_settings_page.dart';
import 'package:chameleonultragui/wear/features/slots/slots_entry.dart';
import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wear_test_services.dart';
import 'slots_test_support.dart';

class _Ctx {
  _Ctx(this.rig, this.fake, this.rotary);
  final WearTestRig rig;
  final SlotsFake fake;
  final RotaryController rotary;
}

Future<_Ctx> _open(
  WidgetTester tester, {
  double textScale = 1.0,
  bool connected = true,
}) async {
  final fake = SlotsFake()..seed();
  final rig = await createWearRig(fake: fake, connected: connected);
  final rotary = RotaryController.fake();
  await rig.pump(
    tester,
    RotaryScope(
      controller: rotary,
      child: Builder(builder: slotsEntry),
    ),
    textScale: textScale,
  );
  await tester.pumpAndSettle();
  return _Ctx(rig, fake, rotary);
}

/// Taps the ring segment of [slot] (0 = top, clockwise).
Future<void> _tapSlot(WidgetTester tester, int slot) async {
  final r = tester.getRect(find.byType(SlotRing));
  final radius = r.width / 2 - 7;
  final angle = (slot + 0.5) * math.pi / 4 - math.pi / 2;
  await tester.tapAt(
    r.center + Offset(radius * math.cos(angle), radius * math.sin(angle)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      60,
      scrollable: find.byType(Scrollable).first,
    );
  }
  expect(f, findsWidgets, reason: 'missing "$text"');
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

/// Finds [text] even when the lazy list has not built it: scrolls to the top
/// and then down until it appears.
Future<Finder> _seek(WidgetTester tester, Finder f) async {
  final sc = find.byType(Scrollable).first;
  await tester.drag(sc, const Offset(0, 2000));
  await tester.pumpAndSettle();
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 60, scrollable: sc);
  }
  return f;
}

List<SlotState> _states(WidgetTester tester) =>
    tester.widget<SlotRing>(find.byType(SlotRing)).states;

void main() {
  group('overview', () {
    testWidgets('shows empty/used/active mix and the focused slot', (
      tester,
    ) async {
      await _open(tester);
      expect(_states(tester), [
        SlotState.used,
        SlotState.empty,
        SlotState.active,
        SlotState.empty,
        SlotState.empty,
        SlotState.used,
        SlotState.empty,
        SlotState.empty,
      ]);
      expect(find.text('Slot 1'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('HF MIFARE 1K'), findsOneWidget);
      expect(find.text('LF EM410X'), findsOneWidget);
    });

    testWidgets('bezel moves the focus, wrapping around', (tester) async {
      final c = await _open(tester);
      c.rotary.feed(1);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Slot 2'), findsOneWidget);
      expect(find.text('Empty'), findsOneWidget);
      c.rotary.feed(-2);
      await tester.pump();
      await tester.pump();
      expect(find.text('Slot 8'), findsOneWidget);
    });

    testWidgets('active slot is labelled in the middle', (tester) async {
      final c = await _open(tester);
      c.rotary.feed(2);
      await tester.pump();
      await tester.pump();
      expect(find.text('Slot 3'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('read failure shows a message and Retry works', (tester) async {
      final fake = SlotsFake()..seed();
      fake.failNext['getSlotTagTypes'] = Exception('link lost');
      final rig = await createWearRig(fake: fake);
      await rig.pump(tester, Builder(builder: slotsEntry));
      await tester.pumpAndSettle();
      expect(find.text('Could not read slots'), findsOneWidget);
      expect(find.textContaining('link lost'), findsOneWidget);
      await _tapText(tester, 'Retry');
      expect(find.byType(SlotRing), findsOneWidget);
    });

    testWidgets('disconnected shows the connect screen', (tester) async {
      await _open(tester, connected: false);
      expect(find.byType(ConnectScreen), findsOneWidget);
      expect(find.byType(SlotRing), findsNothing);
    });

    testWidgets('loads with the minimum of commands', (tester) async {
      final c = await _open(tester);
      expect(c.fake.callLog, [
        'getSlotTagTypes',
        'getEnabledSlots',
        'getSlotTagNames',
        'getActiveSlot',
      ]);
    });
  });

  group('detail', () {
    testWidgets('tap a slot opens its detail', (tester) async {
      await _open(tester);
      await _tapSlot(tester, 2);
      expect(find.byType(SlotDetailPage), findsOneWidget);
      expect(find.text('Slot 3'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('HF · NTAG215'), findsOneWidget);
    });

    testWidgets('activate', (tester) async {
      final c = await _open(tester);
      await _tapSlot(tester, 0);
      await _tapText(tester, 'Activate');
      expect(c.fake.callLog, contains('activateSlot(0)'));
      expect(c.fake.activeSlot, 0);
      expect(find.text('Slot activated', skipOffstage: false), findsOneWidget);
      expect(find.text('Activate'), findsNothing);
    });

    testWidgets('disable then enable HF and LF', (tester) async {
      final c = await _open(tester);
      await _tapSlot(tester, 0);
      await _tapText(tester, 'HF Enabled');
      expect(
        c.fake.callLog,
        containsAllInOrder(['enableSlot(0,hf,false)', 'saveSlotData']),
      );
      expect(c.fake.slots[0].hfEnabled, isFalse);
      await _tapText(tester, 'LF Enabled');
      expect(c.fake.slots[0].lfEnabled, isFalse);
      await _tapText(tester, 'LF Enabled');
      expect(c.fake.slots[0].lfEnabled, isTrue);
      expect(c.fake.callLog, contains('enableSlot(0,lf,true)'));
    });

    testWidgets('enable failure shows an error and keeps the old value', (
      tester,
    ) async {
      final c = await _open(tester);
      await _tapSlot(tester, 0);
      c.fake.failNext['enableSlot'] = Exception('nope');
      await _tapText(tester, 'HF Enabled');
      expect(
        find.textContaining('Failed', skipOffstage: false),
        findsOneWidget,
      );
      final sw = tester.widget<Switch>(find.byType(Switch).first);
      expect(sw.value, isTrue);
      expect(c.fake.slots[0].hfEnabled, isTrue);
    });

    testWidgets('rename HF writes the name and saves', (tester) async {
      final c = await _open(tester);
      await _tapSlot(tester, 0);
      await _tapText(tester, 'Office');
      await tester.enterText(find.byType(TextField), 'Garage');
      await tester.pump();
      await _tapText(tester, 'Save');
      expect(
        c.fake.callLog,
        containsAllInOrder(['setSlotTagName(0,hf)', 'saveSlotData']),
      );
      expect(c.fake.slots[0].hfName, 'Garage');
      expect(find.text('Garage'), findsOneWidget);
    });

    testWidgets('rename LF', (tester) async {
      final c = await _open(tester);
      await _tapSlot(tester, 5);
      await _tapText(tester, 'Fob');
      await tester.enterText(find.byType(TextField), 'Key');
      await tester.pump();
      await _tapText(tester, 'Save');
      expect(c.fake.slots[5].lfName, 'Key');
      expect(c.fake.callLog, contains('setSlotTagName(5,lf)'));
    });

    testWidgets('empty name cannot be saved', (tester) async {
      final c = await _open(tester);
      await _tapSlot(tester, 0);
      await _tapText(tester, 'Office');
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await _tapText(tester, 'Save');
      expect(c.fake.slots[0].hfName, 'Office');
    });

    testWidgets('clear asks for confirmation, then clears', (tester) async {
      final c = await _open(tester);
      await _tapSlot(tester, 0);
      await _tapText(tester, 'Clear HF');
      expect(find.text('Clear HF data?'), findsOneWidget);
      await _tapText(tester, 'Cancel');
      expect(
        c.fake.callLog.where((e) => e.startsWith('deleteSlotInfo')),
        isEmpty,
      );

      await _tapText(tester, 'Clear HF');
      await _tapText(tester, 'Clear');
      expect(
        c.fake.callLog,
        containsAllInOrder([
          'deleteSlotInfo(0,hf)',
          'setSlotTagName(0,hf)',
          'saveSlotData',
        ]),
      );
      expect(c.fake.slots[0].hfType, TagType.unknown);
      expect(find.text('Clear HF'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('returning to the overview reloads the slots', (tester) async {
      final c = await _open(tester);
      await _tapSlot(tester, 5);
      await _tapText(tester, 'Clear LF');
      await _tapText(tester, 'Clear');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(_states(tester)[5], SlotState.empty);
      expect(c.fake.callLog.where((e) => e == 'getSlotTagTypes').length, 2);
    });
  });

  group('settings', () {
    Future<_Ctx> classic(WidgetTester tester, {double scale = 1.0}) async {
      final c = await _open(tester, textScale: scale);
      await _tapSlot(tester, 0);
      await _tapText(tester, 'Settings');
      return c;
    }

    testWidgets('reads once on open (activating the slot first)', (
      tester,
    ) async {
      final c = await classic(tester);
      expect(find.byType(SlotSettingsPage), findsOneWidget);
      final log = c.fake.callLog;
      final i = log.indexOf('activateSlot(0)');
      expect(log.sublist(i), [
        'activateSlot(0)',
        'getMf1EmulatorSettings',
        'getMf1PrngType',
        'mf1GetAntiCollData',
      ]);
      expect(await _seek(tester, find.text('DE AD BE EF')), findsOneWidget);
      expect(
        await _seek(tester, find.textContaining('phone app')),
        findsOneWidget,
      );
    });

    testWidgets('classic toggles write then save', (tester) async {
      final c = await classic(tester);
      final cases = <(String, String, bool Function())>[
        ('Gen1a magic', 'setMf1Gen1aMode(true)', () => c.fake.mf1.isGen1a),
        ('Gen2 magic', 'setMf1Gen2Mode(false)', () => !c.fake.mf1.isGen2),
        (
          'Block 0 anticoll',
          'setMf1UseFirstBlockColl(true)',
          () => c.fake.mf1.isAntiColl,
        ),
        (
          'Detect nonces',
          'setMf1DetectionStatus(true)',
          () => c.fake.mf1.isDetectionEnabled,
        ),
      ];
      for (final (label, call, check) in cases) {
        c.fake.callLog.clear();
        await _tapText(tester, label);
        expect(c.fake.callLog, [call, 'saveSlotData'], reason: label);
        expect(check(), isTrue, reason: label);
        expect(find.text('Saved', skipOffstage: false), findsOneWidget);
      }
    });

    testWidgets('write mode and PRNG pickers', (tester) async {
      final c = await classic(tester);
      await _tapText(tester, 'Write mode');
      await _tapText(tester, 'Shadow');
      expect(c.fake.mf1.writeMode, MifareWriteMode.shadow);
      expect(find.text('Shadow', skipOffstage: false), findsOneWidget);

      await _tapText(tester, 'PRNG');
      await _tapText(tester, 'Hard');
      expect(c.fake.prng, Mf1PrngType.hard);
      expect(c.fake.callLog.where((e) => e == 'saveSlotData').length, 2);
    });

    testWidgets('failed write reverts the toggle and shows the error', (
      tester,
    ) async {
      final c = await classic(tester);
      c.fake.failNext['setMf1Gen1aMode'] = Exception('write failed');
      await _tapText(tester, 'Gen1a magic');
      expect(
        find.textContaining('Failed', skipOffstage: false),
        findsOneWidget,
      );
      final sw = tester.widget<Switch>(find.byType(Switch).first);
      expect(sw.value, isFalse);
      expect(c.fake.callLog, isNot(contains('saveSlotData')));
    });

    testWidgets('failed picker write keeps the previous value', (tester) async {
      final c = await classic(tester);
      c.fake.failNext['setMf1WriteMode'] = Exception('x');
      await _tapText(tester, 'Write mode');
      await _tapText(tester, 'Deceive');
      expect(
        await _seek(tester, find.textContaining('Failed')),
        findsOneWidget,
      );
      expect(find.text('Normal', skipOffstage: false), findsOneWidget);
    });

    testWidgets('read failure shows retry', (tester) async {
      final c = await _open(tester);
      c.fake.failNext['getMf1EmulatorSettings'] = Exception('bad');
      await _tapSlot(tester, 0);
      await _tapText(tester, 'Settings');
      expect(find.text('Could not read settings'), findsOneWidget);
      await _tapText(tester, 'Retry');
      expect(find.text('Gen1a magic'), findsOneWidget);
    });

    testWidgets('ultralight options on the active slot skip activation', (
      tester,
    ) async {
      final c = await _open(tester);
      await _tapSlot(tester, 2);
      c.fake.callLog.clear();
      await _tapText(tester, 'Settings');
      expect(c.fake.callLog, ['mf0NtagGetEmulatorConfig']);
      expect(find.text('Decline', skipOffstage: false), findsOneWidget);

      await _tapText(tester, 'UID magic');
      expect(c.fake.callLog.sublist(1), [
        'mf0SetMagicMode(true)',
        'saveSlotData',
      ]);
      c.fake.callLog.clear();
      await _tapText(tester, 'Detect nonces');
      expect(c.fake.callLog.first, 'mf0NtagSetDetectionEnable(false)');
      await _tapText(tester, 'Write mode');
      await _tapText(tester, 'Normal');
      expect(c.fake.mfu.writeMode, MifareWriteMode.normal);
      expect(c.fake.mfu.isGen2, isTrue);
      expect(c.fake.mfu.isDetectionEnabled, isFalse);
    });
  });

  group('layout at 206 dp', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow at text scale $scale', (tester) async {
        await _open(tester, textScale: scale);
        expect(tester.takeException(), isNull);
        await _tapSlot(tester, 0);
        expect(find.byType(SlotDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _tapText(tester, 'Settings');
        await tester.pumpAndSettle();
        expect(find.byType(SlotSettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long names do not overflow the ring centre', (tester) async {
      final fake = SlotsFake()..seed();
      fake.slots[0].hfName = 'A very long slot name that keeps going';
      final rig = await createWearRig(fake: fake);
      await rig.pump(tester, Builder(builder: slotsEntry), textScale: 1.3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
