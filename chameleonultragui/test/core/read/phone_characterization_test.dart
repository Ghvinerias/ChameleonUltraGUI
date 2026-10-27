// Characterization tests: pin the behavior of the phone read flow (readHFInfo,
// MifareClassicRecovery, ReadCardPageState LF/continuous scans) against the
// FakeChameleonCommunicator. They were written against the pre-refactor code
// and must keep passing unchanged after the headless extraction (Track T1a).
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_card.dart';
import '../../fakes/fake_chameleon_communicator.dart';
import 'phone_harness.dart';

Dictionary emptyDict() => Dictionary(id: '', name: 'empty', keys: []);

Future<(BuildContext, FakeChameleonCommunicator)> mount(
  WidgetTester tester,
  List<FakeCard> cards,
) async {
  final comm = FakeChameleonCommunicator(cards: cards);
  late BuildContext ctx;
  await pumpPhoneApp(
    tester,
    comm,
    Builder(
      builder: (c) {
        ctx = c;
        return const SizedBox();
      },
    ),
  );
  return (ctx, comm);
}

void main() {
  group('HF identify (readHFInfo)', () {
    testWidgets('MFC 1K default keys', (tester) async {
      final (ctx, comm) = await mount(tester, [FakeCard.mfc1kDefaultKeys()]);
      final info = await readHFInfo(ctx, () {});

      expect(compactLog(comm.callLog), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'scan14443aTag',
        'detectMf1Support',
        'send14ARaw(60ff)',
        'send14ARaw(6050)',
        'send14ARaw(603f)',
        'mf1Auth(69,97)',
        'getMf1NTLevel',
        'send14ARaw(6400)',
      ]);
      final (hf, mfc, mfu) = info;
      expect(hf.cardExist, isTrue);
      expect(hf.uid, 'DE AD BE EF');
      expect(hf.sak, '08');
      expect(hf.atqa, '00 04');
      expect(hf.ats, 'No');
      expect(hf.tech, 'Mifare Classic 1K');
      expect(hf.type, TagType.mifare1K);
      expect(mfc.type.name, 'm1k');
      expect(mfc.isEV1, isFalse);
      expect(mfc.ntLevel, NTLevel.weak);
      expect(mfc.hasBackdoor, isFalse);
      expect(mfc.state, MifareClassicState.checkKeys);
      expect(mfc.recovery, isNotNull);
      expect(mfu.version, isNull);
    });

    testWidgets('MFC 1K EV1 pre-fills the signature keys', (tester) async {
      final (ctx, comm) = await mount(tester, [
        FakeCard.mfc1kDefaultKeys(isEV1: true),
      ]);
      final (hf, mfc, _) = await readHFInfo(ctx, () {});
      expect(hf.tech, 'Mifare Classic 1K EV1');
      expect(mfc.isEV1, isTrue);
      final marks = mfc.recovery!.checkMarks;
      expect(marks[16], ChameleonKeyCheckmark.found);
      expect(marks[56], ChameleonKeyCheckmark.found);
      expect(marks[17], ChameleonKeyCheckmark.found);
      expect(marks[57], ChameleonKeyCheckmark.found);
      expect(marks[0], ChameleonKeyCheckmark.none);
      expect(comm.callLog.contains('mf1Auth(69,97)'), isTrue);
    });

    testWidgets('NTAG215 / Mifare Ultralight', (tester) async {
      final (ctx, comm) = await mount(tester, [FakeCard.ntag215()]);
      final (hf, mfc, mfu) = await readHFInfo(ctx, () {});
      expect(compactLog(comm.callLog), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'scan14443aTag',
        'detectMf1Support',
        'send14ARaw(60)',
        'send14ARaw(3c00)',
      ]);
      expect(hf.uid, '04 AA BB CC DD EE 80');
      expect(hf.sak, '00');
      expect(hf.atqa, '00 44');
      expect(hf.tech, 'NTAG215');
      expect(hf.type, TagType.ntag215);
      expect(mfu.version, [0, 4, 4, 2, 1, 0, 17, 3]);
      expect(mfu.signature, hasLength(32));
      expect(mfc.recovery, isNull);
      expect(mfc.state, MifareClassicState.none);
    });

    testWidgets('no card', (tester) async {
      final (ctx, comm) = await mount(tester, [FakeCard.none()]);
      final (hf, mfc, _) = await readHFInfo(ctx, () {});
      expect(compactLog(comm.callLog), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'scan14443aTag',
      ]);
      expect(hf.cardExist, isFalse);
      expect(hf.uid, '');
      expect(mfc.recovery, isNull);
    });

    testWidgets('reader mode already on is not set again', (tester) async {
      final (ctx, comm) = await mount(tester, [FakeCard.none()]);
      comm.readerMode = true;
      await readHFInfo(ctx, () {});
      expect(comm.callLog, ['isReaderDeviceMode', 'scan14443aTag']);
    });

    testWidgets('card removed after anticollision: reported as no card', (
      tester,
    ) async {
      final (ctx, comm) = await mount(tester, [FakeCard.mfc1kDefaultKeys()]);
      comm.failNext['detectMf1Support'] = Exception('lost');
      final (hf, mfc, _) = await readHFInfo(ctx, () {});
      expect(compactLog(comm.callLog), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'scan14443aTag',
        'detectMf1Support',
      ]);
      expect(hf.cardExist, isFalse);
      expect(hf.uid, '');
      expect(mfc.recovery, isNull);
    });

    testWidgets('card removed during MFC type detection', (tester) async {
      final (ctx, comm) = await mount(tester, [FakeCard.mfc1kDefaultKeys()]);
      comm.failNext['send14ARaw'] = Exception('lost');
      final (hf, mfc, _) = await readHFInfo(ctx, () {});
      expect(comm.callLog.last, 'send14ARaw(60ff)');
      expect(hf.cardExist, isFalse);
      expect(mfc.recovery, isNull);
    });

    testWidgets('communication failure before the card answers propagates', (
      tester,
    ) async {
      final (ctx, comm) = await mount(tester, [FakeCard.mfc1kDefaultKeys()]);
      comm.failNext['scan14443aTag'] = Exception('ble down');
      await expectLater(readHFInfo(ctx, () {}), throwsA(isA<Exception>()));
      expect(compactLog(comm.callLog), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'scan14443aTag',
      ]);
    });
  });

  group('MifareClassicRecovery steps', () {
    Future<(MifareClassicRecovery, FakeChameleonCommunicator, List<int>)>
    identified(WidgetTester tester, FakeCard card) async {
      final (ctx, comm) = await mount(tester, [card]);
      final updates = <int>[];
      var n = 0;
      final (_, mfc, _) = await readHFInfo(ctx, () => updates.add(n++));
      comm.callLog.clear();
      return (mfc.recovery!, comm, updates);
    }

    testWidgets('checkKeys finds every default key', (tester) async {
      final (rec, comm, updates) = await identified(
        tester,
        FakeCard.mfc1kDefaultKeys(),
      );
      rec.selectedDictionary = emptyDict();
      await rec.checkKeys();
      final log = compactLog(comm.callLog);
      expect(log.first, 'mf1AuthMultipleKeys(3,96,32)');
      expect(log.length, 32);
      // key B of sector 0 and every later sector is verified with the key
      // found for sector 0 (recheckKey), one mf1Auth each.
      expect(log[1], 'mf1Auth(3,97)');
      expect(log[2], 'mf1Auth(7,96)');
      expect(log.last, 'mf1Auth(63,97)');
      expect(rec.allKeysExists, isTrue);
      expect(rec.state, '');
      expect(rec.error, '');
      expect(rec.keyCheckProgress, isNull);
      expect(
        rec.checkMarks.sublist(0, 16),
        everyElement(ChameleonKeyCheckmark.found),
      );
      expect(bytesToHex(rec.validKeys[0]), 'ffffffffffff');
      expect(updates, isNotEmpty);
    });

    testWidgets('checkKeys with USB chunk size 64 uses one chunk', (
      tester,
    ) async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      late BuildContext ctx;
      await pumpPhoneApp(
        tester,
        comm,
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
        connectionType: ConnectionType.usb,
      );
      final (_, mfc, _) = await readHFInfo(ctx, () {});
      comm.callLog.clear();
      mfc.recovery!.selectedDictionary = emptyDict();
      await mfc.recovery!.checkKeys();
      expect(comm.callLog.first, 'mf1AuthMultipleKeys(3,96,47)');
    });

    testWidgets('card needing a custom key: not found without it', (
      tester,
    ) async {
      final (rec, comm, _) = await identified(
        tester,
        FakeCard.mfc1kCustomKey(),
      );
      rec.selectedDictionary = emptyDict();
      await rec.checkKeys();
      expect(rec.allKeysExists, isFalse);
      // sector 1 key A (index 1) is the only missing key
      expect(rec.checkMarks[1], ChameleonKeyCheckmark.none);
      expect(rec.checkMarks[0], ChameleonKeyCheckmark.found);
      expect(rec.checkMarks[2], ChameleonKeyCheckmark.found);
      expect(rec.checkMarks[41], ChameleonKeyCheckmark.found);
      expect(rec.validKeys[1], isEmpty);
      // sector 1 key A: two chunks (47 default keys / 32 per chunk), no hit
      expect(comm.callLog, contains('mf1AuthMultipleKeys(7,96,32)'));
      expect(comm.callLog, contains('mf1AuthMultipleKeys(7,96,15)'));
      expect(rec.state, '');
    });

    testWidgets('card needing a custom key: found via dictionary', (
      tester,
    ) async {
      final (rec, comm, _) = await identified(
        tester,
        FakeCard.mfc1kCustomKey(),
      );
      rec.selectedDictionary = Dictionary(
        id: 'd',
        name: 'd',
        keys: [Uint8List.fromList(FakeCard.mfc1kCustomKey().keyA[1])],
      );
      await rec.checkKeys();
      expect(rec.allKeysExists, isTrue);
      expect(bytesToHex(rec.validKeys[1]), 'a1b2c3d4e5f6');
      expect(rec.checkMarks[1], ChameleonKeyCheckmark.found);
      // user key is tried first (first chunk of 32), then the 47 built-ins
      expect(comm.callLog.first, 'mf1AuthMultipleKeys(3,96,32)');
      expect(comm.callLog, contains('mf1AuthMultipleKeys(7,96,32)'));
      expect(comm.callLog, isNot(contains('mf1AuthMultipleKeys(7,96,16)')));
    });

    testWidgets('skipDefaultDictionary sends only the user dictionary', (
      tester,
    ) async {
      final (rec, comm, _) = await identified(
        tester,
        FakeCard.mfc1kCustomKey(),
      );
      rec.selectedDictionary = Dictionary(
        id: 'd',
        name: 'd',
        keys: [
          Uint8List.fromList(FakeCard.mfc1kCustomKey().keyA[1]),
          Uint8List.fromList(FakeCard.defaultKey),
        ],
      );
      await rec.checkKeys(skipDefaultDictionary: true);
      expect(comm.callLog.first, 'mf1AuthMultipleKeys(3,96,2)');
      expect(rec.allKeysExists, isTrue);
    });

    testWidgets('dumpData reads every block with the found keys', (
      tester,
    ) async {
      final (rec, comm, _) = await identified(
        tester,
        FakeCard.mfc1kDefaultKeys(),
      );
      rec.selectedDictionary = emptyDict();
      await rec.checkKeys();
      comm.callLog.clear();
      await rec.dumpData();
      expect(comm.callLog.length, 64);
      expect(comm.callLog.first, 'mf1ReadBlock(0,96)');
      expect(comm.callLog.last, 'mf1ReadBlock(63,96)');
      expect(rec.dumpProgress, 63 / 64);
      expect(rec.cardData[0], hasLength(16));
      expect(bytesToHex(rec.cardData[3]), 'ffffffffffffff078069ffffffffffff');
      expect(rec.cardData[64], isEmpty);
    });

    testWidgets('dumpData skips sectors without keys', (tester) async {
      final (rec, comm, _) = await identified(
        tester,
        FakeCard.mfc1kCustomKey(),
      );
      rec.selectedDictionary = emptyDict();
      await rec.checkKeys();
      comm.callLog.clear();
      await rec.dumpData();
      // sector 1 key A is missing: keyType 0 is skipped (empty key) and the
      // block is then read with key B (index 41)
      expect(comm.callLog, contains('mf1ReadBlock(4,97)'));
      expect(comm.callLog, isNot(contains('mf1ReadBlock(4,96)')));
      expect(rec.cardData[4], hasLength(16));
    });

    testWidgets('checkKeys error propagates and keeps partial marks', (
      tester,
    ) async {
      final (rec, comm, _) = await identified(
        tester,
        FakeCard.mfc1kDefaultKeys(),
      );
      rec.selectedDictionary = emptyDict();
      comm.failNext['mf1AuthMultipleKeys'] = Exception('gone');
      await expectLater(rec.checkKeys(), throwsA(isA<Exception>()));
      expect(rec.checkMarks[0], ChameleonKeyCheckmark.checking);
      expect(rec.allKeysExists, isFalse);
    });
  });

  group('LF read (ReadCardPageState.readLFInfo)', () {
    Future<(ReadCardPageState, FakeChameleonCommunicator)> mountPage(
      WidgetTester tester,
      List<FakeCard> cards,
    ) async {
      final comm = FakeChameleonCommunicator(cards: cards);
      await pumpPhoneApp(tester, comm, const ReadCardPage());
      return (tester.state<ReadCardPageState>(find.byType(ReadCardPage)), comm);
    }

    testWidgets('EM410X', (tester) async {
      final (page, comm) = await mountPage(tester, [FakeCard.em410x()]);
      await page.readLFInfo();
      expect(compactLog(comm.callLog), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'readEM410X',
      ]);
      expect(page.lfInfo.cardExist, isTrue);
      expect(page.lfInfo.card, isA<EM410XCard>());
      expect(page.lfInfo.card.toString(), FakeCard.em410x().lf.toString());
      expect(page.scanInProgress, isFalse);
    });

    testWidgets('no LF card probes all five formats in order', (tester) async {
      final (page, comm) = await mountPage(tester, [FakeCard.none()]);
      await page.readLFInfo();
      expect(compactLog(comm.callLog), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'readEM410X',
        'readHIDProx',
        'readViking',
        'readPac',
        'readIoProx',
      ]);
      expect(page.lfInfo.cardExist, isFalse);
      expect(page.lfInfo.card, isNull);
    });
  });

  group('continuous scan (ReadCardPageState)', () {
    Future<(ReadCardPageState, FakeChameleonCommunicator)> mountPage(
      WidgetTester tester,
      List<FakeCard> cards,
    ) async {
      final comm = FakeChameleonCommunicator(cards: cards);
      await pumpPhoneApp(tester, comm, const ReadCardPage());
      return (tester.state<ReadCardPageState>(find.byType(ReadCardPage)), comm);
    }

    testWidgets('HF: probes immediately, then every 2 s, stops at first card', (
      tester,
    ) async {
      final (page, comm) = await mountPage(tester, [
        FakeCard.none(),
        FakeCard.mfc1kDefaultKeys(),
      ]);
      comm.scanScript = [
        FakeCard.none(),
        FakeCard.none(),
        FakeCard.mfc1kDefaultKeys(),
      ];
      await page.startContinuousHFScan();
      expect(comm.hfScanCount, 1);
      expect(page.isContinuousHFScan, isTrue);
      expect(page.hfInfo.cardExist, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(comm.hfScanCount, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(comm.hfScanCount, 2);
      expect(page.isContinuousHFScan, isTrue);

      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(comm.hfScanCount, 3);
      expect(page.isContinuousHFScan, isFalse);
      expect(page.hfInfo.uid, 'DE AD BE EF');
      expect(page.hfInfo.cardExist, isTrue);

      // no further probes after the card was found
      await tester.pump(const Duration(seconds: 10));
      expect(comm.hfScanCount, 3);
    });

    testWidgets('HF: stop button ends the scan', (tester) async {
      final (page, comm) = await mountPage(tester, [FakeCard.none()]);
      await page.startContinuousHFScan();
      await tester.pump(const Duration(seconds: 2));
      expect(comm.hfScanCount, 2);
      page.stopContinuousHFScan();
      expect(page.isContinuousHFScan, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(comm.hfScanCount, 2);
    });

    testWidgets('LF: probes immediately, then every 2 s, stops at first card', (
      tester,
    ) async {
      final (page, comm) = await mountPage(tester, [FakeCard.none()]);
      comm.scanScript = [FakeCard.none(), FakeCard.none(), FakeCard.em410x()];
      await page.startContinuousLFScan();
      expect(comm.lfScanCount, 1);
      expect(page.isContinuousLFScan, isTrue);

      await tester.pump(const Duration(seconds: 2));
      expect(comm.lfScanCount, 2);
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(comm.lfScanCount, 3);
      expect(page.isContinuousLFScan, isFalse);
      expect(page.lfInfo.card, isNotNull);

      await tester.pump(const Duration(seconds: 10));
      expect(comm.lfScanCount, 3);
    });
  });
}
