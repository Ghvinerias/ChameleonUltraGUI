import 'dart:typed_data';

import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/models/card_save.dart';

// Minimal copy of the conversions the phone does when it saves a read card
// (lib/gui/page/read_card.dart saveHFCard/saveLFCard and the dump saves in
// lib/gui/component/mifare/*), working on service results instead of the
// localized `HFCardInfo` strings.

/// Whether [result] holds something worth saving: an MFC with a finished
/// dump, or an Ultralight/NTAG with a known type.
bool canSaveHf(HfReadResult result) {
  if (!result.cardPresent) return false;
  final mfc = result.mifareClassic;
  if (mfc != null) return mfc.completedDepth == MifareClassicDepth.dump;
  return result.mifareUltralight != null && result.type != TagType.unknown;
}

/// Builds the [CardSave] for an HF read. MFC needs a completed dump; MFU is
/// saved info-only (the service does not dump pages). Returns null when the
/// card cannot be saved.
CardSave? cardSaveFromHf(HfReadResult result, {required String name}) {
  final card = result.card;
  if (card == null || !canSaveHf(result)) return null;
  final mfc = result.mifareClassic;
  final mfu = result.mifareUltralight;
  if (mfc != null) {
    final blockCount = mfClassicGetBlockCount(mfc.type, isEV1: mfc.isEV1);
    return CardSave(
      uid: bytesToHexSpace(card.uid),
      sak: card.sak,
      atqa: card.atqa,
      ats: card.ats,
      name: name,
      tag: mfClassicGetChameleonTagType(mfc.type),
      data: [
        for (var i = 0; i < blockCount && i < mfc.blocks.length; i++)
          Uint8List.fromList(mfc.blocks[i]),
      ],
    );
  }
  return CardSave(
    uid: bytesToHexSpace(card.uid),
    sak: card.sak,
    atqa: card.atqa,
    ats: card.ats,
    name: name,
    tag: result.type,
    data: [for (final p in mfu!.pages) Uint8List.fromList(p)],
    extraData: CardSaveExtra(
      ultralightSignature: mfu.signature ?? Uint8List(0),
      ultralightVersion: mfu.version ?? Uint8List(0),
      ultralightCounters: [],
    ),
  );
}

/// LF cards are stored as their id string and tag type, as on the phone.
CardSave cardSaveFromLf(LFCard card, {required String name}) =>
    CardSave(uid: card.toString(), name: name, tag: card.type);

/// Default card name: short type label plus the last three bytes of the id,
/// e.g. `MFC 1K ADBEEF`.
String defaultCardName(TagType type, Uint8List uid) {
  final hex = bytesToHex(uid).toUpperCase();
  final tail = hex.length > 6 ? hex.substring(hex.length - 6) : hex;
  final label = shortTagName(type);
  return tail.isEmpty ? label : '$label $tail';
}

String shortTagName(TagType type) => switch (type) {
  TagType.mifareMini => 'MFC Mini',
  TagType.mifare1K => 'MFC 1K',
  TagType.mifare2K => 'MFC 2K',
  TagType.mifare4K => 'MFC 4K',
  TagType.ntag210 => 'NTAG210',
  TagType.ntag212 => 'NTAG212',
  TagType.ntag213 => 'NTAG213',
  TagType.ntag215 => 'NTAG215',
  TagType.ntag216 => 'NTAG216',
  TagType.ultralight => 'MFU',
  TagType.ultralightC => 'MFU C',
  TagType.ultralight11 => 'MFU EV1',
  TagType.ultralight21 => 'MFU EV1',
  TagType.em410X ||
  TagType.em410X16 ||
  TagType.em410X32 ||
  TagType.em410X64 => 'EM410X',
  TagType.em410XElectra => 'EM410X',
  TagType.hidProx => 'HID',
  TagType.viking => 'Viking',
  TagType.pac => 'PAC',
  TagType.ioProx => 'ioProx',
  TagType.idteck => 'Idteck',
  TagType.hf14a4 => 'HF 14A',
  _ => 'Card',
};

/// Full type label for the result card.
String longTagName(TagType type) => switch (type) {
  TagType.mifareMini => 'Mifare Mini',
  TagType.mifare1K => 'Mifare Classic 1K',
  TagType.mifare2K => 'Mifare Classic 2K',
  TagType.mifare4K => 'Mifare Classic 4K',
  TagType.ntag210 => 'NTAG210',
  TagType.ntag212 => 'NTAG212',
  TagType.ntag213 => 'NTAG213',
  TagType.ntag215 => 'NTAG215',
  TagType.ntag216 => 'NTAG216',
  TagType.ultralight => 'Ultralight',
  TagType.ultralightC => 'Ultralight C',
  TagType.ultralight11 => 'Ultralight EV1 (20)',
  TagType.ultralight21 => 'Ultralight EV1 (41)',
  TagType.em410X => 'EM410X',
  TagType.em410X16 => 'EM410X (16)',
  TagType.em410X32 => 'EM410X (32)',
  TagType.em410X64 => 'EM410X (64)',
  TagType.em410XElectra => 'EM410X Electra',
  TagType.hidProx => 'HID Prox',
  TagType.viking => 'Viking',
  TagType.pac => 'PAC/Stanley',
  TagType.ioProx => 'ioProx',
  TagType.idteck => 'Idteck',
  TagType.hf14a4 => 'ISO14443-4',
  _ => 'Unknown',
};
