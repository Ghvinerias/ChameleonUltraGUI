import 'package:chameleonultragui/wear/features/read/read_controller.dart';
import 'package:chameleonultragui/wear/features/read/read_menu_page.dart';
import 'package:chameleonultragui/wear/features/read/read_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_card.dart';
import '../../../fakes/fake_chameleon_communicator.dart';
import '../../support/wear_test_services.dart';
import 'read_test_support.dart';

/// Scrolls the whole page down and back, failing on any layout exception.
Future<void> scrollThrough(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final scale in [1.0, 1.3]) {
    group('206 dp, text scale $scale', () {
      Future<void> show(
        WidgetTester tester,
        FakeChameleonCommunicator fake,
        ReadMode mode, {
        String? waitFor,
        List<String> taps = const [],
        List<String> waits = const [],
      }) async {
        final rig = await createWearRig(fake: fake);
        await rig.pump(
          tester,
          ReadPage(
            mode: mode,
            effects: RecordingEffects().effects,
            animate: false,
          ),
          textScale: scale,
        );
        if (waitFor != null) await pumpUntil(tester, find.text(waitFor));
        for (var i = 0; i < taps.length; i++) {
          await tapButton(tester, taps[i]);
          await pumpUntil(tester, find.text(waits[i]));
        }
        await scrollThrough(tester);
      }

      testWidgets('menu', (tester) async {
        final rig = await createWearRig();
        await rig.pump(tester, const ReadMenuPage(), textScale: scale);
        await scrollThrough(tester);
      });

      testWidgets('scanning', (tester) async {
        await show(tester, FakeChameleonCommunicator(), ReadMode.scanHf);
      });

      testWidgets('MFC identified, keys checked with missing, 4K-size map', (
        tester,
      ) async {
        await show(
          tester,
          FakeChameleonCommunicator(cards: [FakeCard.mfc1kCustomKey()]),
          ReadMode.hf,
          waitFor: 'Mifare Classic 1K',
          taps: ['Check keys'],
          waits: ['31/32 keys'],
        );
      });

      testWidgets('MFC dumped', (tester) async {
        await show(
          tester,
          FakeChameleonCommunicator(cards: [FakeCard.mfc1kDefaultKeys()]),
          ReadMode.hf,
          waitFor: 'Mifare Classic 1K',
          taps: ['Check keys', 'Dump'],
          waits: ['32/32 keys', 'Save to watch'],
        );
      });

      testWidgets('NTAG215', (tester) async {
        await show(
          tester,
          FakeChameleonCommunicator(cards: [FakeCard.ntag215()]),
          ReadMode.hf,
          waitFor: 'NTAG215',
        );
      });

      testWidgets('EM410X', (tester) async {
        await show(
          tester,
          FakeChameleonCommunicator(cards: [FakeCard.em410x()]),
          ReadMode.lf,
          waitFor: 'EM410X',
        );
      });

      testWidgets('no card', (tester) async {
        await show(
          tester,
          FakeChameleonCommunicator(),
          ReadMode.hf,
          waitFor: 'No card',
        );
      });

      testWidgets('card lost', (tester) async {
        final fake = FakeChameleonCommunicator(
          cards: [FakeCard.mfc1kDefaultKeys()],
        )..failNext['detectMf1Support'] = Exception('x');
        await show(tester, fake, ReadMode.hf, waitFor: 'Card lost');
      });

      testWidgets('save page', (tester) async {
        final fake = FakeChameleonCommunicator(cards: [FakeCard.em410x()]);
        await show(
          tester,
          fake,
          ReadMode.lf,
          waitFor: 'EM410X',
          taps: ['Save to watch'],
          waits: ['Save card'],
        );
      });
    });
  }
}
