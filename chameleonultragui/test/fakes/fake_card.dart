import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart'
    show MifareClassicType, mfClassicGetBlockCount, mfClassicGetSectorByBlock;

/// What a [FakeChameleonCommunicator] has in front of its reader.
///
/// Build with the named factories; each describes one card of the scripted
/// set used by read/slot tests.
class FakeCard {
  final String label;

  /// HF anticollision data; null for LF cards and for "no card".
  final CardData? hf;

  /// Chameleon tag type the read pipeline should end up with.
  final TagType tagType;

  /// Non-null for Mifare Classic cards.
  final MifareClassicType? mfcType;
  final bool isEV1;
  final NTLevel ntLevel;

  /// Mifare Classic: key A / key B per sector.
  final List<Uint8List> keyA;
  final List<Uint8List> keyB;

  /// Mifare Classic: all blocks (16 bytes each), sector trailers carry keys.
  final List<Uint8List> blocks;

  /// Mifare Ultralight / NTAG.
  final Uint8List? mfuVersion;
  final Uint8List? mfuSignature;
  final List<Uint8List> mfuPages;

  /// LF card (EM410X etc.).
  final LFCard? lf;

  FakeCard._({
    required this.label,
    this.hf,
    this.tagType = TagType.unknown,
    this.mfcType,
    this.isEV1 = false,
    this.ntLevel = NTLevel.weak,
    this.keyA = const [],
    this.keyB = const [],
    this.blocks = const [],
    this.mfuVersion,
    this.mfuSignature,
    this.mfuPages = const [],
    this.lf,
  });

  bool get isMifareClassic => mfcType != null;
  bool get isMifareUltralight => mfuVersion != null;
  bool get isPresent => hf != null || lf != null;

  /// Number of readable blocks (MFC) / pages (MFU).
  int get blockCount => blocks.length;

  static final Uint8List defaultKey = Uint8List.fromList([
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
  ]);

  /// Nothing in the field.
  factory FakeCard.none() => FakeCard._(label: 'none');

  /// Mifare Classic 1K whose every key is `FFFFFFFFFFFF`.
  factory FakeCard.mfc1kDefaultKeys({
    List<int>? uid,
    bool isEV1 = false,
    NTLevel ntLevel = NTLevel.weak,
  }) => _mfc(
    isEV1: isEV1,
    ntLevel: ntLevel,
    label: 'mfc1k-default',
    uid: uid ?? const [0xDE, 0xAD, 0xBE, 0xEF],
    type: MifareClassicType.m1k,
    tag: TagType.mifare1K,
    customKeys: const {},
  );

  /// Mifare Classic 1K where key A of [sector] is [customKey]; every other
  /// key is the default. Only found when a dictionary containing
  /// [customKey] is supplied.
  factory FakeCard.mfc1kCustomKey({
    List<int> customKey = const [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6],
    int sector = 1,
    List<int>? uid,
  }) => _mfc(
    label: 'mfc1k-custom',
    uid: uid ?? const [0x11, 0x22, 0x33, 0x44],
    type: MifareClassicType.m1k,
    tag: TagType.mifare1K,
    customKeys: {(sector, 0): Uint8List.fromList(customKey)},
  );

  /// NTAG215 (version `00 04 04 02 01 00 11 03`).
  factory FakeCard.ntag215({List<int>? uid}) {
    final pages = List.generate(
      135,
      (p) => Uint8List.fromList([p, p ^ 0x5A, p ^ 0xA5, 0x00]),
    );
    return FakeCard._(
      label: 'ntag215',
      hf: CardData(
        uid: Uint8List.fromList(
          uid ?? const [0x04, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x80],
        ),
        atqa: Uint8List.fromList([0x00, 0x44]),
        sak: 0x00,
        ats: Uint8List(0),
      ),
      tagType: TagType.ntag215,
      mfuVersion: Uint8List.fromList([
        0x00,
        0x04,
        0x04,
        0x02,
        0x01,
        0x00,
        0x11,
        0x03,
      ]),
      mfuSignature: Uint8List.fromList(List.generate(32, (i) => i)),
      mfuPages: pages,
    );
  }

  /// EM410X low-frequency card.
  factory FakeCard.em410x({List<int>? id}) {
    final card = EM410XCard.fromBytes(
      Uint8List.fromList(id ?? const [0x01, 0x23, 0x45, 0x67, 0x89]),
    );
    return FakeCard._(label: 'em410x', tagType: TagType.em410X, lf: card);
  }

  static FakeCard _mfc({
    required String label,
    required List<int> uid,
    required MifareClassicType type,
    required TagType tag,
    required Map<(int, int), Uint8List> customKeys,
    bool isEV1 = false,
    NTLevel ntLevel = NTLevel.weak,
  }) {
    final blockCount = mfClassicGetBlockCount(type);
    final sectors = mfClassicGetSectorByBlock(blockCount - 1) + 1;
    final keyA = List.generate(
      sectors,
      (s) => customKeys[(s, 0)] ?? Uint8List.fromList(defaultKey),
    );
    final keyB = List.generate(
      sectors,
      (s) => customKeys[(s, 1)] ?? Uint8List.fromList(defaultKey),
    );
    final blocks = List.generate(blockCount, (b) {
      final data = Uint8List(16);
      final sector = mfClassicGetSectorByBlock(b);
      final trailer = (b < 128 ? (b % 4 == 3) : (b % 16 == 15));
      if (trailer) {
        data.setAll(0, keyA[sector]);
        data.setAll(6, [0xFF, 0x07, 0x80, 0x69]);
        data.setAll(10, keyB[sector]);
      } else if (b == 0) {
        data.setAll(0, uid);
      } else {
        for (var i = 0; i < 16; i++) {
          data[i] = (b * 16 + i) & 0xFF;
        }
      }
      return data;
    });
    return FakeCard._(
      label: label,
      hf: CardData(
        uid: Uint8List.fromList(uid),
        atqa: Uint8List.fromList([0x00, 0x04]),
        sak: 0x08,
        ats: Uint8List(0),
      ),
      tagType: tag,
      mfcType: type,
      isEV1: isEV1,
      ntLevel: ntLevel,
      keyA: keyA,
      keyB: keyB,
      blocks: blocks,
    );
  }

  @override
  String toString() => 'FakeCard($label)';
}
