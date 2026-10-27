import 'dart:typed_data';

import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/core/slots/slot_service_impl.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_chameleon_communicator.dart';

/// Characterization tests: the expected command sequences are those issued by
/// the former inline `onTap` of `slot_manager.dart`.
void main() {
  late FakeChameleonCommunicator fake;
  late SlotServiceImpl service;

  setUp(() {
    fake = FakeChameleonCommunicator();
    service = SlotServiceImpl(fake);
  });

  List<Uint8List> blocks(int n, {Set<int> empty = const {}}) => List.generate(
    n,
    (i) => empty.contains(i)
        ? Uint8List(0)
        : Uint8List.fromList(List.filled(16, i & 0xFF)),
  );

  CardSave mfc(TagType tag, List<Uint8List> data, {String name = 'card'}) =>
      CardSave(
        uid: 'DE AD BE EF',
        name: name,
        tag: tag,
        sak: 8,
        atqa: Uint8List.fromList([4, 0]),
        data: data,
      );

  Future<List<SlotUploadEvent>> run(
    CardSave card,
    int slot, {
    String fallback = 'NONAME',
  }) async {
    final up = service.uploadCard(card, slot, emptyNameFallback: fallback);
    final events = <SlotUploadEvent>[];
    up.events.listen(events.add);
    await up.terminal;
    await Future<void>.delayed(Duration.zero);
    return events;
  }

  List<String> setup(int slot, String freq, String type) => [
    'setReaderDeviceMode(false)',
    'enableSlot($slot,$freq,true)',
    'activateSlot($slot)',
    'setSlotType($slot,$type)',
    'setDefaultDataToSlot($slot,$type)',
  ];

  group('Mifare Classic', () {
    test('1K: 8 chunks of 128 bytes, exact order', () async {
      final events = await run(mfc(TagType.mifare1K, blocks(64)), 2);
      expect(fake.callLog, [
        ...setup(2, 'hf', 'mifare1K'),
        'setMf1AntiCollision',
        for (var s = 0; s < 64; s += 8) 'setMf1BlockData($s,128)',
        'setSlotTagName(2,hf)',
        'saveSlotData',
      ]);
      expect(events.first, isA<SlotUploadStarted>());
      expect(events.last, isA<SlotUploadDone>());
      final pct = events.whereType<SlotUploadProgress>().map((e) => e.percent);
      expect(pct.first, 0);
      expect(pct.last, 100);
      expect(pct.toList()..sort(), pct.toList()); // monotonic
      expect(fake.slots[2].blocks.length, 64);
      expect(fake.slots[2].hfName, 'card');
    });

    test('2K and 4K block counts', () async {
      await run(mfc(TagType.mifare2K, blocks(128)), 0);
      expect(
        fake.callLog.where((c) => c.startsWith('setMf1BlockData')).length,
        16,
      );
      fake.callLog.clear();
      await run(mfc(TagType.mifare4K, blocks(256)), 0);
      expect(
        fake.callLog.where((c) => c.startsWith('setMf1BlockData')).length,
        32,
      );
    });

    test('mini', () async {
      await run(mfc(TagType.mifareMini, blocks(20)), 0);
      expect(fake.callLog.where((c) => c.startsWith('setMf1BlockData')), [
        'setMf1BlockData(0,128)',
        'setMf1BlockData(8,128)',
        'setMf1BlockData(16,64)',
      ]);
    });

    test('empty block flushes chunk; legacy start offset preserved', () async {
      await run(mfc(TagType.mifare1K, blocks(64, empty: {4})), 0);
      final writes = fake.callLog
          .where((c) => c.startsWith('setMf1BlockData'))
          .toList();
      // flush at the empty block (0,64); lastSend then = 4 (as before)
      expect(writes.first, 'setMf1BlockData(0,64)');
      expect(writes[1], 'setMf1BlockData(4,128)');
    });

    test('short data array: only present blocks sent', () async {
      await run(mfc(TagType.mifare1K, blocks(3)), 0);
      expect(fake.callLog.where((c) => c.startsWith('setMf1BlockData')), [
        'setMf1BlockData(0,48)',
      ]);
    });

    test('EV1 1K dump becomes 2K without mutating the card', () async {
      final data = blocks(128);
      final card = mfc(TagType.mifare1K, data);
      await run(card, 1);
      expect(fake.callLog, contains('setSlotType(1,mifare2K)'));
      expect(fake.callLog, contains('setDefaultDataToSlot(1,mifare2K)'));
      expect(
        fake.callLog.where((c) => c.startsWith('setMf1BlockData')).length,
        16,
      );
      expect(card.tag, TagType.mifare1K);
      expect(card.data.length, 128);
    });

    test('empty name uses fallback', () async {
      await run(mfc(TagType.mifare1K, blocks(64), name: ''), 0);
      expect(fake.slots[0].hfName, 'NONAME');
    });
  });

  group('Ultralight', () {
    test('NTAG215 with version/signature/counters', () async {
      final card = CardSave(
        uid: '04 AA BB CC DD EE 80',
        name: 'tag',
        tag: TagType.ntag215,
        sak: 0,
        atqa: Uint8List.fromList([0, 0x44]),
        data: List.generate(135, (p) => Uint8List.fromList([p, 0, 0, 0])),
        extraData: CardSaveExtra(
          ultralightVersion: Uint8List.fromList([1, 2, 3]),
          ultralightSignature: Uint8List.fromList([4, 5]),
          ultralightCounters: [7, 8, 9],
        ),
      );
      final events = await run(card, 3);
      expect(fake.callLog, [
        ...setup(3, 'hf', 'ntag215'),
        'setMf1AntiCollision',
        for (var p = 0; p < 135; p++) 'mf0EmulatorWritePages($p)',
        'mf0EmulatorSetVersionData',
        'mf0EmulatorSetSignatureData',
        'mf0EmulatorSetCounterData(0)',
        'mf0EmulatorSetCounterData(1)',
        'mf0EmulatorSetCounterData(2)',
        'mf0ResetAuthCount',
        'setSlotTagName(3,hf)',
        'saveSlotData',
      ]);
      expect(events.whereType<SlotUploadProgress>().last.percent, 100);
    });

    test('plain ultralight: no extras, no counter reset', () async {
      final card = CardSave(
        uid: '04 11 22 33 44 55 66',
        name: 'u',
        tag: TagType.ultralight,
        data: List.generate(16, (p) => Uint8List(4)),
      );
      await run(card, 0);
      expect(fake.callLog.where((c) => !c.startsWith('mf0EmulatorWrite')), [
        ...setup(0, 'hf', 'ultralight'),
        'setMf1AntiCollision',
        'setSlotTagName(0,hf)',
        'saveSlotData',
      ]);
    });
  });

  test('hf14a4', () async {
    final card = CardSave(
      uid: '01 02 03 04',
      name: 'x',
      tag: TagType.hf14a4,
      sak: 0x20,
    );
    final events = await run(card, 5);
    expect(fake.callLog, [
      ...setup(5, 'hf', 'hf14a4'),
      'setMf1AntiCollision',
      'setSlotTagName(5,hf)',
      'saveSlotData',
    ]);
    expect(events.whereType<SlotUploadProgress>().last.percent, 100);
  });

  group('LF', () {
    CardSave lf(TagType t, String uid) =>
        CardSave(uid: uid, name: 'lf', tag: t);

    test('EM410X variants map to em410X / electra', () async {
      for (final t in [
        TagType.em410X,
        TagType.em410X16,
        TagType.em410X32,
        TagType.em410X64,
      ]) {
        fake.callLog.clear();
        await run(lf(t, '01 23 45 67 89'), 4);
        expect(fake.callLog, [
          ...setup(4, 'lf', 'em410X'),
          'setem410XEmulatorID',
          'setSlotTagName(4,lf)',
          'saveSlotData',
        ]);
      }
      fake.callLog.clear();
      await run(lf(TagType.em410XElectra, '01 23 45 67 89'), 4);
      expect(fake.callLog, contains('setSlotType(4,em410XElectra)'));
    });

    test('other LF families', () async {
      final cases = {
        TagType.hidProx: ('sethidProxEmulatorID', '01 00 00 00 05 AA BB CC DD EE 00 00 00'),
        TagType.viking: ('setvikingEmulatorID', '01 02 03 04'),
        TagType.pac: ('setpacEmulatorID', '01 02 03 04'),
        TagType.ioProx: ('setioProxEmulatorID', '01 02 03 04'),
        TagType.idteck: ('setidteckEmulatorID', '01 02 03 04'),
      };
      for (final e in cases.entries) {
        fake.callLog.clear();
        final events = await run(lf(e.key, e.value.$2), 6);
        expect(fake.callLog, [
          ...setup(6, 'lf', e.key.name),
          e.value.$1,
          'setSlotTagName(6,lf)',
          'saveSlotData',
        ], reason: e.key.name);
        expect(events.whereType<SlotUploadProgress>(), isEmpty);
      }
    });
  });

  group('errors / session', () {
    test('unsupported type and invalid slot', () async {
      var e = await run(CardSave(uid: '', name: '', tag: TagType.unknown), 0);
      expect(
        (e.last as SlotUploadFailed).code,
        SlotErrorCode.unsupportedCardType,
      );
      e = await run(mfc(TagType.mifare1K, blocks(64)), 8);
      expect((e.last as SlotUploadFailed).code, SlotErrorCode.invalidSlot);
      expect(fake.callLog, isEmpty);
    });

    test('communication error becomes a code', () async {
      fake.failNext['setSlotType'] = StateError('boom');
      final e = await run(mfc(TagType.mifare1K, blocks(64)), 0);
      expect((e.last as SlotUploadFailed).code, SlotErrorCode.communication);
    });

    test('cancel stops after in-flight command', () async {
      fake.beforeCommand = (call) async {
        if (call.startsWith('setMf1BlockData(8')) {
          await up.cancel();
        }
      };
      final card = mfc(TagType.mifare1K, blocks(64));
      up = service.uploadCard(card, 0);
      final t = await up.terminal;
      expect((t as SlotUploadFailed).code, SlotErrorCode.cancelled);
      expect(fake.callLog.last, 'setMf1BlockData(8,128)');
    });

    test('canUpload', () {
      expect(service.canUpload(mfc(TagType.mifare1K, [])), isTrue);
      expect(
        service.canUpload(CardSave(uid: '', name: '', tag: TagType.unknown)),
        isFalse,
      );
    });
  });

  group('queries', () {
    test('getSlots aggregates in 3 commands', () async {
      fake.slots[1]
        ..hfType = TagType.mifare1K
        ..hfName = 'a'
        ..hfEnabled = true;
      final slots = await service.getSlots();
      expect(slots.length, 8);
      expect(slots[1].hfType, TagType.mifare1K);
      expect(slots[1].hfName, 'a');
      expect(slots[1].hfEnabled, isTrue);
      expect(fake.callLog, [
        'getSlotTagTypes',
        'getEnabledSlots',
        'getSlotTagNames',
      ]);
    });

    test('activate / enable / rename', () async {
      await service.activateSlot(3);
      expect(await service.getActiveSlot(), 3);
      fake.callLog.clear();
      await service.setSlotEnabled(3, TagFrequency.lf, true);
      await service.renameSlot(3, TagFrequency.hf, 'n');
      expect(fake.callLog, [
        'enableSlot(3,lf,true)',
        'saveSlotData',
        'setSlotTagName(3,hf)',
        'saveSlotData',
      ]);
    });
  });
}

late SlotUpload up;
