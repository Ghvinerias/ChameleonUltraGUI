import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/core/read/read_service_impl.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../fakes/fake_card.dart';
import '../../fakes/fake_chameleon_communicator.dart';
import 'fake_key_recovery_backend.dart';
import 'recovery_fake.dart';

ReadServiceImpl serviceFor(
  FakeChameleonCommunicator comm, {
  FakeKeyRecoveryBackend? backend,
  DateTime Function()? now,
}) => ReadServiceImpl(
  communicator: comm,
  backend: backend ?? FakeKeyRecoveryBackend(),
  log: Logger(level: Level.off),
  now: now,
);

/// Collects every event of [session] (listening right away) and returns them
/// once the stream closed.
Future<List<ReadEvent>> drain(ReadSession session) async {
  final events = <ReadEvent>[];
  final done = Completer<void>();
  session.events.listen(events.add, onDone: done.complete);
  await done.future;
  return events;
}

void expectSingleTerminal(List<ReadEvent> events) {
  final terminals = events.where(
    (e) => e is ReadDone || e is ReadFailed || e is ReadCancelled,
  );
  expect(terminals, hasLength(1));
  expect(events.last, same(terminals.single));
}

void main() {
  group('readHf', () {
    test('MFC 1K identify: scanning, card detected, done', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      final session = serviceFor(comm).readHf();
      final events = await drain(session);

      expect(events.map((e) => e.runtimeType), [
        ReadScanning,
        ReadCardDetected,
        ReadDone,
      ]);
      expectSingleTerminal(events);
      expect(session.isFinished, isTrue);
      expect(await session.terminal, same(events.last));

      final result = (events.last as ReadDone).result as HfReadResult;
      expect(result.cardPresent, isTrue);
      expect(bytesToHexSpace(result.card!.uid), 'DE AD BE EF');
      expect(result.type, TagType.mifare1K);
      final mfc = result.mifareClassic!;
      expect(mfc.type, MifareClassicType.m1k);
      expect(mfc.isEV1, isFalse);
      expect(mfc.ntLevel, NTLevel.weak);
      expect(mfc.hasBackdoor, isFalse);
      expect(mfc.sectorStates, hasLength(80));
      expect(mfc.sectorStates, everyElement(SectorKeyState.none));
      expect(mfc.completedDepth, MifareClassicDepth.identify);
      // command order is the one readHFInfo always used
      expect(comm.callLog.take(4), [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'scan14443aTag',
        'detectMf1Support',
      ]);
    });

    test('EV1 pre-fills signature sector keys (contract layout)', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys(isEV1: true)],
      );
      final result =
          ((await serviceFor(comm).readHf().terminal) as ReadDone).result
              as HfReadResult;
      final mfc = result.mifareClassic!;
      expect(mfc.isEV1, isTrue);
      expect(mfc.sectorStates[16 * 2], SectorKeyState.found);
      expect(mfc.sectorStates[16 * 2 + 1], SectorKeyState.found);
      expect(mfc.sectorStates[17 * 2], SectorKeyState.found);
      expect(mfc.sectorStates[17 * 2 + 1], SectorKeyState.found);
      expect(mfc.sectorStates[0], SectorKeyState.none);
      expect(bytesToHex(mfc.keys[17 * 2 + 1]), '4b791bea7bcc');
    });

    test('NTAG215', () async {
      final comm = FakeChameleonCommunicator(cards: [FakeCard.ntag215()]);
      final result =
          ((await serviceFor(comm).readHf().terminal) as ReadDone).result
              as HfReadResult;
      expect(result.type, TagType.ntag215);
      expect(result.mifareClassic, isNull);
      expect(result.mifareUltralight!.version, [0, 4, 4, 2, 1, 0, 17, 3]);
      expect(result.mifareUltralight!.signature, hasLength(32));
    });

    test('no card is a successful read without a card', () async {
      final comm = FakeChameleonCommunicator();
      final session = serviceFor(comm).readHf();
      final events = await drain(session);
      expect(events.map((e) => e.runtimeType), [ReadScanning, ReadDone]);
      final result = (events.last as ReadDone).result as HfReadResult;
      expect(result.cardPresent, isFalse);
      expect(result.type, TagType.unknown);
    });

    test('card removed after anticollision: cardLost', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      comm.failNext['detectMf1Support'] = Exception('lost');
      final terminal = await serviceFor(comm).readHf().terminal;
      expect(terminal, isA<ReadFailed>());
      expect((terminal as ReadFailed).code, ReadErrorCode.cardLost);
    });

    test('communication failure before the card answers', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      comm.failNext['scan14443aTag'] = Exception('ble down');
      final terminal = await serviceFor(comm).readHf().terminal;
      expect((terminal as ReadFailed).code, ReadErrorCode.communication);
      expect(terminal.detail, contains('ble down'));
    });

    test('depth checkKeys: default keys resolve every sector', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      final events = await drain(
        serviceFor(comm).readHf(
          options: const HfReadOptions(depth: MifareClassicDepth.checkKeys),
        ),
      );
      expectSingleTerminal(events);
      final checking = events.whereType<ReadCheckingKeys>().toList();
      expect(checking, isNotEmpty);
      expect(checking.first.keyCount, 47);
      expect(checking.first.chunksTotal, 2);
      expect(checking.first.sectorsTotal, 16);
      expect(checking.last.sectorsDone, 16);
      expect(checking.last.sectorStates, hasLength(80));
      final mfc =
          ((events.last as ReadDone).result as HfReadResult).mifareClassic!;
      expect(mfc.allKeysFound, isTrue);
      expect(mfc.completedDepth, MifareClassicDepth.checkKeys);
      expect(
        mfc.sectorStates.sublist(0, 32),
        everyElement(SectorKeyState.found),
      );
      expect(bytesToHex(mfc.keys[0]), 'ffffffffffff');
    });

    test('depth checkKeys: custom key found via dictionary', () async {
      final card = FakeCard.mfc1kCustomKey();
      final comm = FakeChameleonCommunicator(cards: [card]);
      final dictionary = Dictionary(
        id: 'd',
        name: 'd',
        keys: [Uint8List.fromList(card.keyA[1])],
      );
      final mfc =
          (((await serviceFor(comm)
                              .readHf(
                                options: HfReadOptions(
                                  depth: MifareClassicDepth.checkKeys,
                                  dictionaries: [dictionary],
                                ),
                              )
                              .terminal)
                          as ReadDone)
                      .result
                  as HfReadResult)
              .mifareClassic!;
      expect(mfc.allKeysFound, isTrue);
      expect(bytesToHex(mfc.keys[1 * 2]), 'a1b2c3d4e5f6');
      expect(comm.callLog, contains('mf1AuthMultipleKeys(3,96,32)'));
    });

    test('depth checkKeys: custom key missing without a dictionary', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kCustomKey()],
      );
      final mfc =
          (((await serviceFor(comm)
                              .readHf(
                                options: const HfReadOptions(
                                  depth: MifareClassicDepth.checkKeys,
                                ),
                              )
                              .terminal)
                          as ReadDone)
                      .result
                  as HfReadResult)
              .mifareClassic!;
      expect(mfc.allKeysFound, isFalse);
      expect(mfc.sectorStates[1 * 2], SectorKeyState.none);
      expect(mfc.sectorStates[0], SectorKeyState.found);
    });

    test(
      'skipDefaultDictionary and primaryDictionaryId order the key list',
      () async {
        final comm = FakeChameleonCommunicator(
          cards: [FakeCard.mfc1kCustomKey()],
        );
        final a = Dictionary(id: 'a', name: 'a', keys: [Uint8List(6)]);
        final b = Dictionary(
          id: 'b',
          name: 'b',
          keys: [Uint8List.fromList(FakeCard.mfc1kCustomKey().keyA[1])],
        );
        await serviceFor(comm)
            .readHf(
              options: HfReadOptions(
                depth: MifareClassicDepth.checkKeys,
                dictionaries: [a, b],
                primaryDictionaryId: 'b',
                skipDefaultDictionary: true,
              ),
            )
            .terminal;
        expect(comm.callLog, contains('mf1AuthMultipleKeys(3,96,2)'));
      },
    );

    test('depth dump: reads blocks and reports progress', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      final events = await drain(
        serviceFor(
          comm,
        ).readHf(options: const HfReadOptions(depth: MifareClassicDepth.dump)),
      );
      final dump = events.whereType<ReadDumpProgress>().toList();
      expect(dump, hasLength(64));
      expect(dump.last.blocksTotal, 64);
      final mfc =
          ((events.last as ReadDone).result as HfReadResult).mifareClassic!;
      expect(mfc.completedDepth, MifareClassicDepth.dump);
      expect(mfc.blocks, hasLength(256));
      expect(bytesToHex(mfc.blocks[3]), 'ffffffffffffff078069ffffffffffff');
      expect(mfc.blocks[64], isEmpty);
    });
  });

  group('continueMifareClassic', () {
    test('steps identify -> keys -> dump on the same card', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      final service = serviceFor(comm);
      var mfc =
          (((await service.readHf().terminal) as ReadDone).result
                  as HfReadResult)
              .mifareClassic!;

      mfc =
          (((await service
                              .continueMifareClassic(
                                mfc,
                                depth: MifareClassicDepth.checkKeys,
                              )
                              .terminal)
                          as ReadDone)
                      .result
                  as HfReadResult)
              .mifareClassic!;
      expect(mfc.completedDepth, MifareClassicDepth.checkKeys);
      expect(mfc.allKeysFound, isTrue);

      comm.callLog.clear();
      mfc =
          (((await service
                              .continueMifareClassic(
                                mfc,
                                depth: MifareClassicDepth.dump,
                              )
                              .terminal)
                          as ReadDone)
                      .result
                  as HfReadResult)
              .mifareClassic!;
      expect(mfc.completedDepth, MifareClassicDepth.dump);
      // all keys known: recovery is skipped, only block reads
      expect(comm.callLog, everyElement(startsWith('mf1ReadBlock')));
      expect(bytesToHex(mfc.blocks[0]), isNot(''));
    });
  });

  group('key recovery', () {
    final custom = FakeCard.mfc1kCustomKey(sector: 1);

    test('nested attack recovers the missing key via the backend', () async {
      final comm = RecoveryFake([custom]);
      final key = custom.keyA[1];
      final backend = FakeKeyRecoveryBackend(
        results: {
          'nested': [key.fold<int>(0, (acc, b) => (acc << 8) | b)],
        },
      );
      final events = await drain(
        serviceFor(comm, backend: backend).readHf(
          options: const HfReadOptions(depth: MifareClassicDepth.recoverKeys),
        ),
      );
      expectSingleTerminal(events);
      expect(events.last, isA<ReadDone>());
      final mfc =
          ((events.last as ReadDone).result as HfReadResult).mifareClassic!;
      expect(mfc.allKeysFound, isTrue);
      expect(bytesToHex(mfc.keys[2]), 'a1b2c3d4e5f6');
      expect(backend.calls, ['nested']);

      final recovery = events.whereType<ReadRecoveryProgress>().toList();
      expect(recovery.first.attack, RecoveryAttack.detecting);
      expect(recovery.first.sector, isNull);
      final nested = recovery.where((e) => e.attack == RecoveryAttack.nested);
      expect(nested.map((e) => e.step), [
        RecoveryStep.collectingNonces,
        RecoveryStep.recoveringKey,
      ]);
      expect(nested.first.sector, 1);
      expect(nested.first.keyType, 0);
    });

    test(
      'hardnested needed but disallowed ends with hardnestedUnavailable',
      () async {
        final hardCard = FakeCard.mfc1kCustomKey(sector: 1);
        final comm = RecoveryFake([hardCard])..ntLevelOverride();
        final backend = FakeKeyRecoveryBackend();
        final terminal = await serviceFor(comm, backend: backend)
            .readHf(
              options: const HfReadOptions(
                depth: MifareClassicDepth.recoverKeys,
                allowHardnested: false,
              ),
            )
            .terminal;
        expect(terminal, isA<ReadFailed>());
        expect(
          (terminal as ReadFailed).code,
          ReadErrorCode.hardnestedUnavailable,
        );
        expect(backend.calls, isEmpty);
        // the attack itself never started (it needs the PRNG distance first)
        expect(comm.callLog, isNot(contains('getMf1NTDistance')));
      },
    );

    test(
      'hardnested allowed: nonce collection runs (old firmware reply)',
      () async {
        final comm = RecoveryFake([custom])..ntLevelOverride();
        final events = await drain(
          serviceFor(comm).readHf(
            options: const HfReadOptions(depth: MifareClassicDepth.recoverKeys),
          ),
        );
        final failed = events.last as ReadFailed;
        expect(failed.code, ReadErrorCode.recoveryFailed);
        expect(failed.detail, 'firmware_too_old');
        expect(
          events.whereType<ReadRecoveryProgress>().where(
            (e) => e.attack == RecoveryAttack.hardnested,
          ),
          isNotEmpty,
        );
      },
    );

    test('unavailable native library maps to recoveryUnavailable', () async {
      final comm = RecoveryFake([custom]);
      final backend = FakeKeyRecoveryBackend(unavailable: true);
      final terminal = await serviceFor(comm, backend: backend)
          .readHf(
            options: const HfReadOptions(depth: MifareClassicDepth.recoverKeys),
          )
          .terminal;
      expect((terminal as ReadFailed).code, ReadErrorCode.recoveryUnavailable);
    });

    test('nothing found and no key to start from: noKeysForRecovery', () async {
      final comm = RecoveryFake([custom]);
      // a key-checked state in which no key was found
      final from = MifareClassicReadState(
        type: MifareClassicType.m1k,
        isEV1: false,
        sectorStates: List.filled(80, SectorKeyState.none),
        keys: List.generate(80, (_) => Uint8List(0)),
        blocks: List.generate(256, (_) => Uint8List(0)),
        completedDepth: MifareClassicDepth.checkKeys,
      );
      final terminal = await serviceFor(comm)
          .continueMifareClassic(from, depth: MifareClassicDepth.recoverKeys)
          .terminal;
      // the fake has no darkside support, so no key can be obtained
      expect(terminal, isA<ReadFailed>());
      expect((terminal as ReadFailed).code, ReadErrorCode.noKeysForRecovery);
    });
  });

  group('readLf', () {
    test('EM410X', () async {
      final comm = FakeChameleonCommunicator(cards: [FakeCard.em410x()]);
      final events = await drain(serviceFor(comm).readLf());
      expect(events.map((e) => e.runtimeType), [
        ReadScanning,
        ReadCardDetected,
        ReadDone,
      ]);
      final result = (events.last as ReadDone).result as LfReadResult;
      expect(result.card, isA<EM410XCard>());
      expect((events[1] as ReadCardDetected).lfCard, same(result.card));
      expect(comm.callLog, [
        'isReaderDeviceMode',
        'setReaderDeviceMode(true)',
        'readEM410X',
      ]);
    });

    test('no card probes EM410X, HID, Viking, PAC, IoProx in order', () async {
      final comm = FakeChameleonCommunicator();
      final result =
          ((await serviceFor(comm).readLf().terminal) as ReadDone).result
              as LfReadResult;
      expect(result.cardPresent, isFalse);
      expect(comm.callLog.skip(2), [
        'readEM410X',
        'readHIDProx',
        'readViking',
        'readPac',
        'readIoProx',
      ]);
    });
  });

  group('sessions', () {
    test('a second session while one runs throws StateError', () async {
      final comm = FakeChameleonCommunicator();
      final service = serviceFor(comm);
      final first = service.readHf();
      expect(() => service.readLf(), throwsStateError);
      await first.terminal;
      // finished: starting again is fine
      await service.readLf().terminal;
    });

    test('cancel stops commands and ends with ReadCancelled', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      final service = serviceFor(comm);
      late ReadSession session;
      comm.beforeCommand = (call) async {
        if (call == 'detectMf1Support') unawaited(session.cancel());
      };
      session = service.readHf(
        options: const HfReadOptions(depth: MifareClassicDepth.checkKeys),
      );
      final events = await drain(session);
      expect(events.last, isA<ReadCancelled>());
      expect((events.last as ReadCancelled).timedOut, isFalse);
      expectSingleTerminal(events);
      // no command was issued after the in-flight detectMf1Support
      expect(comm.callLog.last, 'detectMf1Support');
    });

    test('cancel is idempotent and a no-op after the end', () async {
      final comm = FakeChameleonCommunicator();
      final session = serviceFor(comm).readHf();
      await session.terminal;
      await session.cancel();
      await session.cancel();
      expect(session.isFinished, isTrue);
    });

    test('cancel during key checking leaves no pending commands', () async {
      final comm = FakeChameleonCommunicator(
        cards: [FakeCard.mfc1kDefaultKeys()],
      );
      final service = serviceFor(comm);
      late ReadSession session;
      var seen = 0;
      comm.beforeCommand = (call) async {
        if (call.startsWith('mf1Auth(') && ++seen == 5) {
          unawaited(session.cancel());
        }
      };
      session = service.readHf(
        options: const HfReadOptions(depth: MifareClassicDepth.checkKeys),
      );
      final terminal = await session.terminal;
      expect(terminal, isA<ReadCancelled>());
      final issued = comm.callLog.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(comm.callLog.length, issued);
    });
  });

  group('continuous scans', () {
    testWidgets('HF: 2 s interval, stops at first card', (tester) async {
      final comm = FakeChameleonCommunicator();
      comm.scanScript = [
        FakeCard.none(),
        FakeCard.none(),
        FakeCard.mfc1kDefaultKeys(),
      ];
      final session = serviceFor(
        comm,
        now: () => tester.binding.clock.now(),
      ).startContinuousHfScan();
      final events = <ReadEvent>[];
      session.events.listen(events.add);

      await tester.pump();
      expect(comm.hfScanCount, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(comm.hfScanCount, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(comm.hfScanCount, 2);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(comm.hfScanCount, 3);
      expect(session.isFinished, isTrue);
      expect(events.whereType<ReadScanning>().map((e) => e.attempt), [1, 2, 3]);
      expect(events.last, isA<ReadDone>());
      expectSingleTerminal(events);
      final result = (events.last as ReadDone).result as HfReadResult;
      expect(bytesToHexSpace(result.card!.uid), 'DE AD BE EF');

      await tester.pump(const Duration(seconds: 10));
      expect(comm.hfScanCount, 3);
    });

    testWidgets('LF: 2 s interval, stops at first card', (tester) async {
      final comm = FakeChameleonCommunicator();
      comm.scanScript = [FakeCard.none(), FakeCard.em410x()];
      final session = serviceFor(
        comm,
        now: () => tester.binding.clock.now(),
      ).startContinuousLfScan();
      await tester.pump();
      expect(comm.lfScanCount, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(comm.lfScanCount, 2);
      final terminal = await session.terminal;
      expect(((terminal as ReadDone).result as LfReadResult).card, isNotNull);
    });

    testWidgets('1 minute cap ends with ReadCancelled(timedOut)', (
      tester,
    ) async {
      final comm = FakeChameleonCommunicator();
      final session = serviceFor(
        comm,
        now: () => tester.binding.clock.now(),
      ).startContinuousHfScan();
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      final terminal = await session.terminal;
      expect(terminal, isA<ReadCancelled>());
      expect((terminal as ReadCancelled).timedOut, isTrue);
      // probes at t = 0, 2, ..., 58 s, like the phone's timer
      expect(comm.hfScanCount, 30);
    });

    testWidgets('cancel stops the scan, also while waiting', (tester) async {
      final comm = FakeChameleonCommunicator();
      final session = serviceFor(
        comm,
        now: () => tester.binding.clock.now(),
      ).startContinuousHfScan();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(comm.hfScanCount, 2);
      await session.cancel();
      final terminal = await session.terminal;
      expect(terminal, isA<ReadCancelled>());
      expect((terminal as ReadCancelled).timedOut, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(comm.hfScanCount, 2);
    });

    testWidgets('stopOnFound=false keeps scanning and reports every card', (
      tester,
    ) async {
      final comm = FakeChameleonCommunicator(cards: [FakeCard.em410x()]);
      final session = serviceFor(comm, now: () => tester.binding.clock.now())
          .startContinuousLfScan(
            options: const ContinuousScanOptions(stopOnFound: false),
          );
      final events = <ReadEvent>[];
      session.events.listen(events.add);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(session.isFinished, isFalse);
      expect(events.whereType<ReadCardDetected>(), hasLength(3));
      await session.cancel();
      expect(events.last, isA<ReadCancelled>());
      expectSingleTerminal(events);
    });
  });
}
