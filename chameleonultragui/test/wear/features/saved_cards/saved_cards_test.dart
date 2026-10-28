import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/core/slots/slot_service_impl.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/wear/connection/ui/connect_screen.dart';
import 'package:chameleonultragui/wear/features/saved_cards/card_detail_page.dart';
import 'package:chameleonultragui/wear/features/saved_cards/saved_cards_entry.dart';
import 'package:chameleonultragui/wear/features/saved_cards/saved_cards_model.dart';
import 'package:chameleonultragui/wear/features/saved_cards/saved_cards_page.dart';
import 'package:chameleonultragui/wear/features/saved_cards/strings.dart';
import 'package:chameleonultragui/wear/widgets/progress_ring.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_chameleon_communicator.dart';
import '../../support/wear_test_services.dart';

CardSave mfc1k({
  String id = 'mfc',
  String name = 'Office door',
  String? folderId,
  int? updatedAt,
  int sectorsWithKeys = 12,
}) {
  final data = List<Uint8List>.generate(64, (b) {
    final isTrailer = b % 4 == 3;
    if (isTrailer && b ~/ 4 >= sectorsWithKeys) return Uint8List(0);
    return Uint8List.fromList(List.filled(16, b));
  });
  return CardSave(
    id: id,
    uid: 'DEADBEEF',
    name: name,
    tag: TagType.mifare1K,
    sak: 0x08,
    atqa: Uint8List.fromList([0x00, 0x04]),
    color: Colors.blue,
    folderId: folderId,
    updatedAt: updatedAt,
    data: data,
  );
}

CardSave ntag215({String id = 'ntag'}) => CardSave(
  id: id,
  uid: '04A1B2C3D4E5F6',
  name: 'Tag',
  tag: TagType.ntag215,
  sak: 0,
  atqa: Uint8List.fromList([0x44, 0x00]),
  data: List.generate(135, (i) => Uint8List.fromList([i, 0, 0, 0])),
);

CardSave em410x({String id = 'em'}) =>
    CardSave(id: id, uid: '1234567890', name: 'Fob', tag: TagType.em410X);

CardSave unsupported() =>
    CardSave(id: 'unk', uid: '00', name: 'Mystery', tag: TagType.unknown);

Map<String, Object> seed(
  List<CardSave> cards, {
  List<CardFolder> folders = const [],
}) => {
  'cards': cards.map((c) => c.toJson()).toList(),
  if (folders.isNotEmpty)
    'card_folders': folders.map((f) => f.toJson()).toList(),
};

Future<void> openFirstCard(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Finder button(String label) => find.widgetWithText(FilledButton, label);

/// Taps slot [i] (0 at the top, clockwise) on the slot ring.
Future<void> tapSlot(WidgetTester tester, int i) async {
  final ring = tester.getRect(find.byType(SlotRing));
  final angle = i * math.pi / 4;
  final r = ring.width / 2 - 6;
  await tester.tapAt(
    ring.center + Offset(r * math.sin(angle), -r * math.cos(angle)),
  );
  await tester.pumpAndSettle();
}

/// Pumps real-ish time until [f] shows (uploads use timers pumpAndSettle
/// does not wait for).
Future<void> pumpUntil(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    60,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  final f = button(label);
  await tester.scrollUntilVisible(
    f,
    60,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('list', () {
    testWidgets('empty state explains where cards come from', (tester) async {
      final rig = await createWearRig();
      await rig.pump(tester, const SavedCardsPage());
      await tester.pumpAndSettle();
      expect(find.text(SavedCardsStrings.emptyTitle), findsOneWidget);
      expect(find.text(SavedCardsStrings.emptyBody), findsOneWidget);
    });

    testWidgets('shows name, type and UID without a connection', (
      tester,
    ) async {
      final rig = await createWearRig(
        connected: false,
        prefsValues: seed([mfc1k(), em410x()]),
      );
      await rig.pump(tester, const SavedCardsPage());
      await tester.pumpAndSettle();
      expect(find.text('Office door'), findsOneWidget);
      expect(find.textContaining('Mifare Classic 1K'), findsOneWidget);
      expect(find.textContaining('DEADBEEF'), findsOneWidget);
      expect(find.text('Fob'), findsOneWidget);
      expect(find.textContaining('EM410X'), findsOneWidget);
    });

    testWidgets('entry builds the page', (tester) async {
      final rig = await createWearRig(prefsValues: seed([mfc1k()]));
      await rig.pump(tester, Builder(builder: savedCardsEntry));
      await tester.pumpAndSettle();
      expect(find.byType(SavedCardsPage), findsOneWidget);
    });

    testWidgets('folders become sections with paths, newest first', (
      tester,
    ) async {
      final work = CardFolder(id: 'w', name: 'Work');
      final doors = CardFolder(id: 'd', name: 'Doors', parentId: 'w');
      final rig = await createWearRig(
        prefsValues: seed(
          [
            mfc1k(id: 'a', name: 'Old', folderId: 'd', updatedAt: 10),
            mfc1k(id: 'b', name: 'New', folderId: 'd', updatedAt: 99),
            mfc1k(id: 'c', name: 'Loose'),
          ],
          folders: [work, doors],
        ),
      );
      await rig.pump(tester, const SavedCardsPage());
      await tester.pumpAndSettle();
      expect(find.text(SavedCardsStrings.unfiled), findsOneWidget);
      await reveal(tester, find.text('Old'));
      expect(find.text('Work / Doors'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('New')).dy,
        lessThan(tester.getTopLeft(find.text('Old')).dy),
      );
    });

    test('rows: orphan folder shows by its name, cycles terminate', () {
      final rows = buildSavedRows(
        [mfc1k(id: 'x', folderId: 'a')],
        [
          CardFolder(id: 'a', name: 'A', parentId: 'b'),
          CardFolder(id: 'b', name: 'B', parentId: 'a'),
        ],
      );
      expect(rows.first, isA<FolderHeaderRow>());
      expect((rows.first as FolderHeaderRow).path, 'B / A');
      final orphan = buildSavedRows(
        [mfc1k(folderId: 'a')],
        [CardFolder(id: 'a', name: 'Solo', parentId: 'gone')],
      );
      expect((orphan.first as FolderHeaderRow).path, 'Solo');
    });

    testWidgets('500 cards scroll without errors', (tester) async {
      final cards = [
        for (var i = 0; i < 500; i++)
          mfc1k(id: 'c$i', name: 'Card $i', updatedAt: 1000 - i),
      ];
      final rig = await createWearRig(prefsValues: seed(cards));
      await rig.pump(tester, const SavedCardsPage());
      await tester.pumpAndSettle();
      expect(find.text('Card 0'), findsOneWidget);
      // Lazy: far rows are not built.
      expect(find.text('Card 400'), findsNothing);
      await tester.dragUntilVisible(
        find.text('Card 300'),
        find.byType(ListView),
        const Offset(0, -400),
        maxIteration: 400,
      );
      await tester.pumpAndSettle();
      expect(find.text('Card 300'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow at text scale $scale', (tester) async {
        final rig = await createWearRig(
          prefsValues: seed(
            [mfc1k(name: 'A rather long card name that wraps'), ntag215()],
            folders: [CardFolder(id: 'f', name: 'Some long folder name')],
          ),
        );
        await rig.pump(tester, const SavedCardsPage(), textScale: scale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('detail', () {
    Future<void> openDetail(
      WidgetTester tester,
      CardSave card, {
      double scale = 1.0,
      bool connected = true,
    }) async {
      final rig = await createWearRig(
        connected: connected,
        prefsValues: seed([card]),
      );
      await rig.pump(tester, CardDetailPage(card: card), textScale: scale);
      await tester.pumpAndSettle();
    }

    testWidgets('Mifare Classic: ids, color chip and dump summary', (
      tester,
    ) async {
      await openDetail(tester, mfc1k());
      expect(find.text('Office door'), findsOneWidget);
      expect(find.textContaining('Mifare Classic 1K'), findsOneWidget);
      expect(find.byKey(const Key('cardColorChip')), findsOneWidget);
      expect(find.textContaining('DEADBEEF', findRichText: true), findsWidgets);
      expect(find.textContaining('00 04', findRichText: true), findsWidgets);
      await reveal(
        tester,
        find.textContaining('keys known', findRichText: true),
      );
      expect(
        find.textContaining('12/16 sectors keys known', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('60/64 blocks', findRichText: true),
        findsOneWidget,
      );
      expect(button(SavedCardsStrings.loadIntoSlot), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(button(SavedCardsStrings.loadIntoSlot))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('NTAG: pages', (tester) async {
      await openDetail(tester, ntag215());
      expect(find.textContaining('NTAG215'), findsOneWidget);
      expect(
        find.textContaining('135 pages', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('LF card: no ATQA/SAK, ID only', (tester) async {
      await openDetail(tester, em410x());
      expect(find.textContaining('EM410X'), findsWidgets);
      expect(find.textContaining('ATQA', findRichText: true), findsNothing);
      expect(find.textContaining('SAK', findRichText: true), findsNothing);
      expect(
        find.textContaining('ID only', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('unsupported type: load disabled with the reason', (
      tester,
    ) async {
      await openDetail(tester, unsupported());
      expect(
        tester
            .widget<FilledButton>(button(SavedCardsStrings.loadIntoSlot))
            .onPressed,
        isNull,
      );
      await reveal(tester, find.text(SavedCardsStrings.cannotLoad));
      expect(find.text(SavedCardsStrings.cannotLoad), findsOneWidget);
    });

    test('cardTypeLoadable matches SlotServiceImpl.canUpload', () {
      final service = SlotServiceImpl(FakeChameleonCommunicator());
      for (final tag in TagType.values) {
        final card = CardSave(uid: '00', name: 'x', tag: tag);
        expect(cardTypeLoadable(tag), service.canUpload(card), reason: '$tag');
      }
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow at text scale $scale', (tester) async {
        await openDetail(
          tester,
          mfc1k(name: 'Very long name for a card'),
          scale: scale,
        );
        await tester.dragUntilVisible(
          button(SavedCardsStrings.delete),
          find.byType(ListView),
          const Offset(0, -150),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('actions', () {
    testWidgets('rename persists and bumps updatedAt', (tester) async {
      final card = mfc1k(updatedAt: 5);
      final rig = await createWearRig(prefsValues: seed([card]));
      await rig.pump(tester, const SavedCardsPage());
      await tester.pumpAndSettle();
      await openFirstCard(tester, 'Office door');
      await tapButton(tester, SavedCardsStrings.rename);
      await tester.enterText(find.byType(TextField), '  Garage  ');
      await tester.pump();
      await tapButton(tester, SavedCardsStrings.save);

      final stored = (await rig.services.cardStore.getCard('mfc'))!;
      expect(stored.name, 'Garage');
      expect(stored.updatedAt, greaterThan(5));
      // The data survived the round trip.
      expect(stored.data.length, 64);
    });

    testWidgets('rename with empty text cannot be saved', (tester) async {
      final rig = await createWearRig(prefsValues: seed([mfc1k()]));
      await rig.pump(tester, CardDetailPage(card: mfc1k()));
      await tester.pumpAndSettle();
      await tapButton(tester, SavedCardsStrings.rename);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(button(SavedCardsStrings.save)).onPressed,
        isNull,
      );
    });

    testWidgets('delete asks first, then records a tombstone', (tester) async {
      final rig = await createWearRig(prefsValues: seed([mfc1k(), em410x()]));
      await rig.pump(tester, const SavedCardsPage());
      await tester.pumpAndSettle();
      await openFirstCard(tester, 'Office door');

      // Cancel keeps the card.
      await tapButton(tester, SavedCardsStrings.delete);
      expect(find.text(SavedCardsStrings.deleteTitle), findsOneWidget);
      await tapButton(tester, SavedCardsStrings.cancel);
      expect(await rig.services.cardStore.getCard('mfc'), isNotNull);

      await tapButton(tester, SavedCardsStrings.delete);
      await tapButton(tester, SavedCardsStrings.delete);
      expect(await rig.services.cardStore.getCard('mfc'), isNull);
      final tombs = await rig.services.cardStore.getTombstones();
      expect(
        tombs.where((t) => t.kind == SyncEntityKind.card && t.id == 'mfc'),
        hasLength(1),
      );
      // Back on the list, which no longer shows it.
      expect(find.text('Office door'), findsNothing);
      expect(find.text('Fob'), findsOneWidget);
    });
  });

  group('load into slot', () {
    Future<WearTestRig> toSlotPicker(
      WidgetTester tester, {
      FakeChameleonCommunicator? fake,
      CardSave? card,
    }) async {
      final c = card ?? mfc1k();
      final rig = await createWearRig(fake: fake, prefsValues: seed([c]));
      await rig.pump(tester, CardDetailPage(card: c));
      await tester.pumpAndSettle();
      await tapButton(tester, SavedCardsStrings.loadIntoSlot);
      return rig;
    }

    testWidgets('empty slot: no confirmation, uploads with progress', (
      tester,
    ) async {
      final fake = FakeChameleonCommunicator();
      // Hold the upload at its first block write to observe the progress UI.
      final gate = Completer<void>();
      fake.beforeCommand = (call) async {
        if (call.startsWith('setMf1BlockData')) await gate.future;
      };
      await toSlotPicker(tester, fake: fake);
      await tapSlot(tester, 2);
      await tapButton(tester, 'Load into 3');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.text(SavedCardsStrings.uploading(2)), findsOneWidget);

      gate.complete();
      await pumpUntil(tester, find.text(SavedCardsStrings.uploaded(2)));
      expect(find.text(SavedCardsStrings.uploaded(2)), findsOneWidget);
      expect(fake.slots[2].hfType, TagType.mifare1K);
      expect(fake.slots[2].hfName, 'Office door');
      expect(fake.slots[2].blocks, isNotEmpty);
      expect(fake.activeSlot, 2);
      expect(fake.callLog, contains('activateSlot(2)'));

      await tapButton(tester, SavedCardsStrings.done);
      expect(find.byType(CardDetailPage), findsOneWidget);
    });

    testWidgets('slot in use needs overwrite confirmation', (tester) async {
      final fake = FakeChameleonCommunicator();
      fake.slots[2]
        ..hfType = TagType.ntag215
        ..hfName = 'Keep me';
      await toSlotPicker(tester, fake: fake);
      await tapSlot(tester, 2);
      await tapButton(tester, 'Load into 3');
      expect(find.text(SavedCardsStrings.overwriteTitle(2)), findsOneWidget);
      expect(find.textContaining('Keep me'), findsOneWidget);

      // Decline: back to the picker, nothing written.
      await tapButton(tester, SavedCardsStrings.cancel);
      expect(fake.slots[2].hfName, 'Keep me');
      expect(fake.callLog.where((c) => c.startsWith('setSlotType')), isEmpty);

      // Accept (a fresh picker, so choose the slot again).
      await tapSlot(tester, 2);
      await tapButton(tester, 'Load into 3');
      await tapButton(tester, SavedCardsStrings.overwrite);
      await pumpUntil(tester, find.text(SavedCardsStrings.uploaded(2)));
      expect(find.text(SavedCardsStrings.uploaded(2)), findsOneWidget);
      expect(fake.slots[2].hfType, TagType.mifare1K);
      expect(fake.slots[2].hfName, 'Office door');
    });

    testWidgets('upload failure shows a short message and can retry', (
      tester,
    ) async {
      final fake = FakeChameleonCommunicator();
      fake.failNext['setSlotType'] = Exception('boom: raw detail');
      await toSlotPicker(tester, fake: fake);
      await tapSlot(tester, 1);
      await tapButton(tester, 'Load into 2');
      await pumpUntil(tester, button(SavedCardsStrings.retry));
      expect(find.textContaining('boom'), findsNothing);
      expect(
        find.text(SavedCardsStrings.uploadError(SlotErrorCode.communication)),
        findsOneWidget,
      );
      expect(button(SavedCardsStrings.retry), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disconnected: connect screen instead of the flow', (
      tester,
    ) async {
      final c = mfc1k();
      final rig = await createWearRig(connected: false, prefsValues: seed([c]));
      await rig.pump(tester, CardDetailPage(card: c));
      await tester.pumpAndSettle();
      await tapButton(tester, SavedCardsStrings.loadIntoSlot);
      expect(find.byType(ConnectScreen), findsOneWidget);
    });

    testWidgets('backing out of the picker returns to the detail', (
      tester,
    ) async {
      await toSlotPicker(tester);
      final NavigatorState nav = tester.state(find.byType(Navigator));
      nav.pop(); // picker
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsOneWidget);
    });
  });
}
