import 'package:chameleonultragui/core/read/read_service_impl.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_selection.dart';
import 'package:chameleonultragui/wear/features/read/read_controller.dart';
import 'package:chameleonultragui/wear/features/read/read_entry.dart';
import 'package:chameleonultragui/wear/features/read/read_page.dart';
import 'package:chameleonultragui/wear/widgets/scan_pulse.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../core/read/fake_key_recovery_backend.dart';
import '../../../core/read/recovery_fake.dart';
import '../../../fakes/fake_card.dart';
import '../../../fakes/fake_chameleon_communicator.dart';
import '../../support/wear_test_services.dart';
import 'read_test_support.dart';

Finder attempt(String n) =>
    find.descendant(of: find.byType(ScanPulse), matching: find.text(n));

Widget page(ReadMode mode, RecordingEffects fx) =>
    ReadPage(mode: mode, effects: fx.effects, animate: false);

void main() {
  group('HF single read', () {
    testWidgets('MFC default keys: identify, check keys, dump, save', (
      tester,
    ) async {
      final rig = await createWearRig(
        fake: FakeChameleonCommunicator(cards: [FakeCard.mfc1kDefaultKeys()]),
      );
      await rig.pump(tester, page(ReadMode.hf, RecordingEffects()));
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
      expect(find.text('DE AD BE EF'), findsOneWidget);
      expect(find.text('00 04'), findsOneWidget);
      expect(find.text('08'), findsOneWidget);
      await pumpUntil(tester, find.text('none'));

      await tapButton(tester, 'Check keys');
      await pumpUntil(tester, find.text('32/32 keys'));
      expect(find.text('Recover keys'), findsNothing);

      await tapButton(tester, 'Dump');
      await pumpUntil(tester, find.text('Save to watch'));

      await tapButton(tester, 'Save to watch');
      await pumpUntil(tester, find.byType(TextField));
      expect(find.text('MFC 1K ADBEEF'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Office door');
      await tapButton(tester, 'Save');
      await pumpUntil(tester, find.text('Saved'));

      final cards = await rig.services.cardStore.getCards();
      expect(cards, hasLength(1));
      expect(cards.single.name, 'Office door');
      expect(cards.single.tag, TagType.mifare1K);
      expect(cards.single.data, hasLength(64));
      expect(cards.single.data[3].sublist(0, 6), List.filled(6, 0xFF));
    });

    testWidgets('MFC with a custom key needs the selected dictionary', (
      tester,
    ) async {
      final card = FakeCard.mfc1kCustomKey();
      var rig = await createWearRig(
        fake: FakeChameleonCommunicator(cards: [card]),
      );
      await rig.pump(tester, page(ReadMode.hf, RecordingEffects()));
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
      await tapButton(tester, 'Check keys');
      await pumpUntil(tester, find.text('31/32 keys'));
      expect(find.text('Recover keys'), findsWidgets);
    });

    testWidgets('selected dictionary finds the custom key', (tester) async {
      final card = FakeCard.mfc1kCustomKey();
      final rig = await createWearRig(
        fake: FakeChameleonCommunicator(cards: [card]),
      );
      await rig.services.dictionaryStore.saveDictionary(
        Dictionary(
          id: 'd1',
          name: 'mine',
          keyLength: 12,
          keys: [bytes(card.keyA[1])],
        ),
      );
      await WearDictionarySelection.setSelectedIds({'d1'});
      await rig.pump(tester, page(ReadMode.hf, RecordingEffects()));
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
      await tapButton(tester, 'Check keys');
      await pumpUntil(tester, find.text('32/32 keys'));
    });

    testWidgets('NTAG215 summary and save', (tester) async {
      final rig = await createWearRig(
        fake: FakeChameleonCommunicator(cards: [FakeCard.ntag215()]),
      );
      await rig.pump(tester, page(ReadMode.hf, RecordingEffects()));
      await pumpUntil(tester, find.text('NTAG215'));
      await pumpUntil(tester, find.text('00 04 04 02 01 00 11 03'));
      await pumpUntil(tester, find.text('yes'));
      expect(find.text('Check keys'), findsNothing);

      await tapButton(tester, 'Save to watch');
      await pumpUntil(tester, find.byType(TextField));
      await tapButton(tester, 'Save');
      await pumpUntil(tester, find.text('Saved'));
      final saved = (await rig.services.cardStore.getCards()).single;
      expect(saved.tag, TagType.ntag215);
      expect(saved.extraData.ultralightSignature, hasLength(32));
    });

    testWidgets('no card, then retry finds it', (tester) async {
      final fake = FakeChameleonCommunicator();
      final rig = await createWearRig(fake: fake);
      await rig.pump(tester, page(ReadMode.hf, RecordingEffects()));
      await pumpUntil(tester, find.text('No card'));
      fake.presentCard(FakeCard.ntag215());
      await tapButton(tester, 'Retry');
      await pumpUntil(tester, find.text('NTAG215'));
    });

    testWidgets('card removed mid-read shows card lost and retry works', (
      tester,
    ) async {
      final fake = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      fake.failNext['detectMf1Support'] = Exception('gone');
      final rig = await createWearRig(fake: fake);
      await rig.pump(tester, page(ReadMode.hf, RecordingEffects()));
      await pumpUntil(tester, find.text('Card lost'));
      await tapButton(tester, 'Retry');
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
    });

    testWidgets('hardnested needed: phone app message, no backend call', (
      tester,
    ) async {
      final comm = RecoveryFake([FakeCard.mfc1kCustomKey(sector: 1)])
        ..ntLevelOverride();
      final rig = await createWearRig(fake: comm);
      final backend = FakeKeyRecoveryBackend();
      final services = ServicesWithRead(
        rig.services,
        ReadServiceImpl(
          communicator: comm,
          backend: backend,
          log: Logger(level: Level.off),
        ),
      );
      await pumpWithServices(
        tester,
        services,
        page(ReadMode.hf, RecordingEffects()),
      );
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
      await tapButton(tester, 'Check keys');
      await pumpUntil(tester, find.text('31/32 keys'));
      await tapButton(tester, 'Recover keys');
      await pumpUntil(tester, find.text('Needs the phone app'));
      expect(backend.calls, isEmpty);
      expect(comm.callLog, isNot(contains('getMf1NTDistance')));
      // back to the keys result
      await tapButton(tester, 'Back');
      await pumpUntil(tester, find.text('31/32 keys'));
    });

    testWidgets('nested recovery shows progress, then all keys', (
      tester,
    ) async {
      final card = FakeCard.mfc1kCustomKey(sector: 1);
      final comm = RecoveryFake([card]);
      final key = card.keyA[1].fold<int>(0, (a, b) => (a << 8) | b);
      final rig = await createWearRig(fake: comm);
      final services = ServicesWithRead(
        rig.services,
        ReadServiceImpl(
          communicator: comm,
          backend: FakeKeyRecoveryBackend(
            results: {
              'nested': [key],
            },
          ),
          log: Logger(level: Level.off),
        ),
      );
      await pumpWithServices(
        tester,
        services,
        page(ReadMode.hf, RecordingEffects()),
      );
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
      await tapButton(tester, 'Check keys');
      await pumpUntil(tester, find.text('31/32 keys'));
      await tapButton(tester, 'Recover keys');
      await pumpUntil(tester, find.text('32/32 keys'));
    });
  });

  group('LF', () {
    testWidgets('EM410X read, write to slot', (tester) async {
      final fake = FakeChameleonCommunicator(cards: [FakeCard.em410x()]);
      final rig = await createWearRig(fake: fake);
      await rig.pump(tester, page(ReadMode.lf, RecordingEffects()));
      await pumpUntil(tester, find.text('EM410X'));

      await tapButton(tester, 'Write to slot');
      await pumpUntil(tester, find.byType(SlotRing));
      await pumpFor(tester, const Duration(milliseconds: 200));
      final ring = tester.getRect(find.byType(SlotRing));
      await tester.tapAt(Offset(ring.right - 7, ring.center.dy));
      await tester.pump();
      await tapButton(tester, 'Write to 3');
      await pumpUntil(tester, find.text('Slot 3 is ready.'));
      expect(fake.slots[2].lfType, TagType.em410X);
      expect(fake.callLog, contains('saveSlotData'));
    });
  });

  group('continuous scan', () {
    testWidgets('stops at the first card, haptic, wakelock released', (
      tester,
    ) async {
      final fake = FakeChameleonCommunicator();
      fake.scanScript = [
        FakeCard.none(),
        FakeCard.none(),
        FakeCard.mfc1kDefaultKeys(),
      ];
      final rig = await createWearRig(fake: fake);
      final fx = RecordingEffects();
      await rig.pump(tester, page(ReadMode.scanHf, fx));
      await pumpUntil(tester, attempt('2'));
      expect(fx.awake, [true]);
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
      expect(fake.hfScanCount, 3);
      expect(fx.haptics, 1);
      expect(fx.awake, [true, false]);
      await pumpFor(tester, const Duration(seconds: 5));
      expect(fake.hfScanCount, 3);
    });

    testWidgets('manual stop ends the scan', (tester) async {
      final fake = FakeChameleonCommunicator();
      final rig = await createWearRig(fake: fake);
      final fx = RecordingEffects();
      await rig.pump(tester, page(ReadMode.scanLf, fx));
      await pumpUntil(tester, attempt('3'));
      await tapButton(tester, 'Stop');
      await pumpUntil(tester, find.text('Stopped'));
      final n = fake.lfScanCount;
      await pumpFor(tester, const Duration(seconds: 5));
      expect(fake.lfScanCount, n);
      expect(fx.awake, [true, false]);
      expect(fx.haptics, 0);
    });

    testWidgets('leaving the page cancels BLE traffic', (tester) async {
      final fake = FakeChameleonCommunicator();
      final rig = await createWearRig(fake: fake);
      final fx = RecordingEffects();
      await rig.pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => page(ReadMode.scanHf, fx)),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUntil(tester, attempt('2'));
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await pumpFor(tester, const Duration(milliseconds: 100));
      final n = fake.callLog.length;
      await pumpFor(tester, const Duration(seconds: 8));
      expect(fake.callLog.length, n);
      expect(fx.awake, [true, false]);
    });

    testWidgets('leaving mid key check stops the commands', (tester) async {
      final fake = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      final rig = await createWearRig(fake: fake);
      await rig.pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => page(ReadMode.hf, RecordingEffects()),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUntil(tester, find.text('Mifare Classic 1K'));
      fake.beforeCommand = (call) async {
        if (call.startsWith('mf1Auth')) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      };
      await tapButton(tester, 'Check keys');
      await pumpFor(tester, const Duration(milliseconds: 300));
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await pumpFor(tester, const Duration(milliseconds: 500));
      final n = fake.callLog.length;
      await pumpFor(tester, const Duration(seconds: 5));
      expect(fake.callLog.length, n);
    });
  });

  group('entry', () {
    testWidgets('menu lists the four reads behind the connection gate', (
      tester,
    ) async {
      final rig = await createWearRig(connected: false);
      await rig.pump(tester, Builder(builder: readEntry));
      expect(find.text('Read HF'), findsNothing);

      final connected = await createWearRig();
      await connected.pump(tester, Builder(builder: readEntry));
      expect(find.text('Read HF'), findsOneWidget);
      expect(find.text('Read LF'), findsOneWidget);
      expect(find.text('Scan HF (continuous)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Scan LF (continuous)'),
        60,
        scrollable: find.byType(Scrollable).first,
      );
    });
  });
}
