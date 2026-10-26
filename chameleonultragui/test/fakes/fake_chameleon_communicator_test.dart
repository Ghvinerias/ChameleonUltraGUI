import 'dart:typed_data';

import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_card.dart';
import 'fake_chameleon_communicator.dart';

void main() {
  test('no card present', () async {
    final c = FakeChameleonCommunicator(cards: [FakeCard.none()]);
    expect(await c.scan14443aTag(), isNull);
    expect(await c.readEM410X(), isNull);
    expect(await c.detectMf1Support(), isFalse);
  });

  test('MFC 1K default keys: type detection and key check', () async {
    final c = FakeChameleonCommunicator(cards: [FakeCard.mfc1kDefaultKeys()]);
    final card = await c.scan14443aTag();
    expect(card, isNotNull);
    expect(card!.sak, 0x08);
    expect(await c.detectMf1Support(), isTrue);
    expect(await mfClassicGetType(c), MifareClassicType.m1k);
    expect(await mfClassicHasBackdoor(c), isFalse);
    expect(await c.mf1Auth(0x45, 0x61, gMifareClassicKeys[3]), isFalse);
    expect(await c.getMf1NTLevel(), NTLevel.weak);

    for (var sector = 0; sector < 16; sector++) {
      final trailer = mfClassicGetSectorTrailerBlockBySector(sector);
      for (final keyType in [0x60, 0x61]) {
        final key = await c.mf1AuthMultipleKeys(trailer, keyType, [
          Uint8List(6),
          gMifareClassicKeys.first,
        ]);
        expect(key, gMifareClassicKeys.first);
      }
    }
    final key = FakeCard.defaultKey;
    expect(await c.mf1ReadBlock(3, 0x60, key), hasLength(16));
    expect(await c.mf1ReadBlock(3, 0x60, Uint8List(6)), isEmpty);
  });

  test('MFC 1K custom key needs the dictionary key', () async {
    final custom = Uint8List.fromList([0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]);
    final c = FakeChameleonCommunicator(cards: [FakeCard.mfc1kCustomKey()]);
    final trailer = mfClassicGetSectorTrailerBlockBySector(1);
    expect(
      await c.mf1AuthMultipleKeys(trailer, 0x60, gMifareClassicKeys),
      isNull,
    );
    expect(
      await c.mf1AuthMultipleKeys(trailer, 0x60, [
        ...gMifareClassicKeys,
        custom,
      ]),
      custom,
    );
    // key B of the same sector is still default
    expect(
      await c.mf1AuthMultipleKeys(trailer, 0x61, gMifareClassicKeys),
      FakeCard.defaultKey,
    );
  });

  test('MFC EV1 probe', () async {
    final c = FakeChameleonCommunicator(
      cards: [FakeCard.mfc1kDefaultKeys(isEV1: true)],
    );
    await c.scan14443aTag();
    expect(await c.mf1Auth(0x45, 0x61, gMifareClassicKeys[3]), isTrue);
  });

  test('NTAG215 via real Ultralight scan helper', () async {
    final c = FakeChameleonCommunicator(cards: [FakeCard.ntag215()]);
    expect(await c.scan14443aTag(), isNotNull);
    expect(await c.detectMf1Support(), isFalse);
    final (type, info) = await performMifareUltralightScan(
      c,
      MifareUltralightInfo(),
    );
    expect(type, TagType.ntag215);
    expect(info.signature, hasLength(32));
  });

  test('EM410X LF', () async {
    final c = FakeChameleonCommunicator(cards: [FakeCard.em410x()]);
    expect(await c.scan14443aTag(), isNull);
    final lf = await c.readEM410X();
    expect(lf, isNotNull);
    expect(lf!.type, TagType.em410X);
  });

  test('scanScript advances one card per scan attempt', () async {
    final c = FakeChameleonCommunicator()
      ..scanScript = [FakeCard.none(), FakeCard.none(), FakeCard.ntag215()];
    expect(await c.scan14443aTag(), isNull);
    expect(await c.scan14443aTag(), isNull);
    expect(await c.scan14443aTag(), isNotNull);
    expect(await c.scan14443aTag(), isNotNull); // last repeats
    expect(c.hfScanCount, 4);
  });

  test('slot upload sequence is recorded', () async {
    final c = FakeChameleonCommunicator();
    await c.setReaderDeviceMode(false);
    await c.enableSlot(2, TagFrequency.hf, true);
    await c.activateSlot(2);
    await c.setSlotType(2, TagType.mifare1K);
    await c.setDefaultDataToSlot(2, TagType.mifare1K);
    await c.setMf1AntiCollision(
      CardData(
        uid: Uint8List.fromList([1, 2, 3, 4]),
        atqa: Uint8List.fromList([0, 4]),
        sak: 8,
        ats: Uint8List(0),
      ),
    );
    await c.setMf1BlockData(0, Uint8List(32));
    await c.setSlotTagName(2, 'Card', TagFrequency.hf);
    await c.saveSlotData();

    expect((await c.getSlotTagTypes())[2].hf, TagType.mifare1K);
    expect((await c.getEnabledSlots())[2].hf, isTrue);
    expect((await c.getSlotTagNames())[2].hf, 'Card');
    expect(await c.getActiveSlot(), 2);
    expect(c.slots[2].blocks.keys, [0, 1]);
    expect(c.saved, isTrue);
    expect(c.callLog.first, 'setReaderDeviceMode(false)');
  });

  test('LF slot id goes to the LF half', () async {
    final c = FakeChameleonCommunicator();
    await c.setSlotType(0, TagType.em410X);
    await c.setEM410XEmulatorID(Uint8List.fromList([1, 2, 3, 4, 5]));
    expect((await c.getSlotTagTypes())[0].lf, TagType.em410X);
    expect(c.slots[0].lfIds[TagType.em410X], [1, 2, 3, 4, 5]);
  });

  test('unfaked commands fail loudly with the command name', () async {
    final c = FakeChameleonCommunicator();
    expect(() => c.getBatteryCharge(), throwsA(isA<UnimplementedError>()));
  });

  test('failNext injects an error once', () async {
    final c = FakeChameleonCommunicator()..failNext['scan14443aTag'] = 'boom';
    await expectLater(c.scan14443aTag(), throwsA('boom'));
    expect(await c.scan14443aTag(), isNull);
  });
}
