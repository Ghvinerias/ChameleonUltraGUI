import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart'
    show gMifareClassicKeys, mfClassicGetSectorByBlock;
import 'package:logger/logger.dart';

import 'fake_card.dart';

/// Emulator-side state of one slot, as written by upload flows.
class FakeSlot {
  TagType hfType = TagType.unknown;
  TagType lfType = TagType.unknown;
  bool hfEnabled = false;
  bool lfEnabled = false;
  String hfName = '';
  String lfName = '';

  /// Mifare Classic block data written via `setMf1BlockData` (block -> 16 B).
  final Map<int, Uint8List> blocks = {};

  /// Ultralight pages written via `mf0EmulatorWritePages` (page -> 4 B).
  final Map<int, Uint8List> pages = {};
  Uint8List? mfuVersion;
  Uint8List? mfuSignature;
  final Map<int, int> mfuCounters = {};
  CardData? antiCollision;

  /// LF emulator id by tag type.
  final Map<TagType, Uint8List> lfIds = {};

  void reset() {
    blocks.clear();
    pages.clear();
    mfuVersion = null;
    mfuSignature = null;
    mfuCounters.clear();
    antiCollision = null;
    lfIds.clear();
  }
}

/// A [ChameleonCommunicator] with no serial port, driven by scripted cards.
///
/// HOW IT IS BUILT. `ChameleonCommunicator` takes an optional
/// `AbstractSerial` and only dereferences it inside `sendCmd`. We therefore
/// subclass it, construct it with no port, and override at the *method*
/// level every command the read and slot flows use (`scan14443aTag`,
/// `detectMf1Support`, `send14ARaw`, `mf1Auth*`, LF reads, slot getters and
/// setters, ...). No byte frames are built, so there is no fake serial to
/// maintain. Any method that is NOT overridden ends up in [sendCmd], which
/// we override to throw [UnimplementedError] naming the command, so a flow
/// that needs more of the device fails loudly and tells you what to add.
/// (A fake `AbstractSerial` replaying hex was rejected: `EmulatorSerial`
/// already does that and cannot drive stateful read flows.)
///
/// SCRIPTING. [cards] is the available set; [present] picks which one is in
/// the field. Set [scanScript] to make successive scan *attempts* see
/// successive cards (one attempt = one `scan14443aTag` call for HF, one
/// `readEM410X` call for LF); the last entry repeats. Use it to test
/// continuous scans, e.g. `[none, none, mfc1k]`.
class FakeChameleonCommunicator extends ChameleonCommunicator {
  final List<FakeCard> cards;
  List<FakeCard>? scanScript;

  FakeCard _current;
  int _attempts = 0;

  bool readerMode = false;
  int activeSlot = 0;
  bool saved = false;
  final List<FakeSlot> slots = List.generate(8, (_) => FakeSlot());

  /// Every overridden call in order, e.g. `scan14443aTag`, `mf1Auth(3,97)`.
  final List<String> callLog = [];

  /// Number of `scan14443aTag` and `readEM410X` calls.
  int hfScanCount = 0;
  int lfScanCount = 0;

  /// Optional failure injection: throws this on the next call of the named
  /// method and clears itself.
  final Map<String, Object> failNext = {};

  /// Awaited at the start of every command; lets tests interleave
  /// cancellation (`await Future.delayed`) with in-flight commands.
  Future<void> Function(String call)? beforeCommand;

  FakeChameleonCommunicator({List<FakeCard>? cards, Logger? log})
    : cards = cards ?? [FakeCard.none()],
      _current = (cards == null || cards.isEmpty)
          ? FakeCard.none()
          : cards.first,
      super(log ?? Logger(level: Level.off));

  /// Card currently in the field.
  FakeCard get current => _current;

  /// Puts `cards[index]` into the field.
  void present(int index) => _current = cards[index];

  /// Puts an arbitrary card in the field.
  void presentCard(FakeCard card) => _current = card;

  Future<void> _enter(String call) async {
    callLog.add(call);
    final err = failNext.remove(call.split('(').first);
    if (err != null) throw err;
    if (beforeCommand != null) await beforeCommand!(call);
  }

  void _attempt() {
    final script = scanScript;
    if (script != null && script.isNotEmpty) {
      _current =
          script[_attempts < script.length ? _attempts : script.length - 1];
    }
    _attempts++;
  }

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) {
    throw UnimplementedError(
      'FakeChameleonCommunicator: command ${cmd.name} is not faked. '
      'Override the calling method in test/fakes/fake_chameleon_communicator.dart.',
    );
  }

  // ---- device mode -------------------------------------------------------

  @override
  Future<bool> isReaderDeviceMode() async {
    await _enter('isReaderDeviceMode');
    return readerMode;
  }

  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {
    await _enter('setReaderDeviceMode($readerMode)');
    this.readerMode = readerMode;
  }

  // ---- HF reader ---------------------------------------------------------

  @override
  Future<CardData?> scan14443aTag() async {
    await _enter('scan14443aTag');
    hfScanCount++;
    _attempt();
    return _current.hf;
  }

  @override
  Future<bool> detectMf1Support() async {
    await _enter('detectMf1Support');
    return _current.isMifareClassic;
  }

  @override
  Future<NTLevel> getMf1NTLevel() async {
    await _enter('getMf1NTLevel');
    return _current.ntLevel;
  }

  @override
  Future<(int, NestedNonces, NestedNonces, Uint8List)?>
  getMf1StaticEncryptedNestedAcquire({
    int sectorCount = 16,
    int startingSector = 0,
  }) async {
    await _enter('getMf1StaticEncryptedNestedAcquire');
    return null; // no backdoor on any scripted card
  }

  int? _sectorOf(int block) {
    final card = _current;
    if (!card.isMifareClassic || block < 0 || block >= card.blockCount) {
      return null;
    }
    return mfClassicGetSectorByBlock(block);
  }

  bool _keyMatches(int block, int keyType, Uint8List key) {
    final sector = _sectorOf(block);
    if (sector == null) return false;
    final expected = (keyType == 0x60 ? _current.keyA : _current.keyB)[sector];
    return bytesToHex(expected) == bytesToHex(key);
  }

  @override
  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async {
    await _enter('mf1Auth($block,$keyType)');
    if (_current.isEV1 && block == 0x45 && keyType == 0x61) {
      // EV1 signature sector probe used by readHFInfo.
      return bytesToHex(key) == bytesToHex(gMifareClassicKeys[3]);
    }
    return _keyMatches(block, keyType, key);
  }

  @override
  Future<Uint8List?> mf1AuthMultipleKeys(
    int block,
    int keyType,
    List<Uint8List> keys,
  ) async {
    await _enter('mf1AuthMultipleKeys($block,$keyType,${keys.length})');
    for (final key in keys) {
      if (_keyMatches(block, keyType, key)) return key;
    }
    return null;
  }

  @override
  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async {
    await _enter('mf1ReadBlock($block,$keyType)');
    if (!_keyMatches(block, keyType, key)) return Uint8List(0);
    return Uint8List.fromList(_current.blocks[block]);
  }

  /// Answers the raw frames that type detection uses:
  ///  * MFC `60 NN` (auth block NN) -> 4-byte nonce if the block exists
  ///  * `64 00` (backdoor probe) -> empty
  ///  * MFU `60` (GET_VERSION), `3C 00` (READ_SIG), `1A 00` (ULC auth),
  ///    `30 NN` (READ page NN).
  @override
  Future<Uint8List> send14ARaw(
    Uint8List data, {
    int respTimeoutMs = 100,
    int? bitLen,
    bool activateRfField = true,
    bool waitResponse = true,
    bool appendCrc = true,
    bool autoSelect = true,
    bool keepRfField = false,
    bool checkResponseCrc = true,
  }) async {
    await _enter('send14ARaw(${bytesToHex(data)})');
    final card = _current;
    if (card.isMifareClassic) {
      if (data.length == 2 && data[0] == 0x60) {
        return data[1] < card.blockCount
            ? Uint8List.fromList([0x12, 0x34, 0x56, 0x78])
            : Uint8List(0);
      }
      return Uint8List(0);
    }
    if (card.isMifareUltralight) {
      if (data.length == 1 && data[0] == 0x60) return card.mfuVersion!;
      if (data.length == 2 && data[0] == 0x3C) return card.mfuSignature!;
      if (data.length == 2 && data[0] == 0x30) {
        final page = data[1];
        if (page >= card.mfuPages.length) return Uint8List(0);
        return Uint8List.fromList(
          List.generate(
            16,
            (i) => page + i < card.mfuPages.length
                ? card.mfuPages[page + i][0]
                : 0,
          ),
        );
      }
    }
    return Uint8List(0);
  }

  // ---- LF reader ---------------------------------------------------------

  @override
  Future<EM410XCard?> readEM410X() async {
    await _enter('readEM410X');
    lfScanCount++;
    _attempt();
    final lf = _current.lf;
    return lf is EM410XCard ? lf : null;
  }

  @override
  Future<HIDCard?> readHIDProx() async {
    await _enter('readHIDProx');
    final lf = _current.lf;
    return lf is HIDCard ? lf : null;
  }

  @override
  Future<VikingCard?> readViking() async {
    await _enter('readViking');
    final lf = _current.lf;
    return lf is VikingCard ? lf : null;
  }

  @override
  Future<PacCard?> readPac() async {
    await _enter('readPac');
    final lf = _current.lf;
    return lf is PacCard ? lf : null;
  }

  @override
  Future<IoProxCard?> readIoProx() async {
    await _enter('readIoProx');
    final lf = _current.lf;
    return lf is IoProxCard ? lf : null;
  }

  // ---- slots -------------------------------------------------------------

  static bool _isLf(TagType t) =>
      isEM410X(t) ||
      t == TagType.hidProx ||
      t == TagType.viking ||
      t == TagType.pac ||
      t == TagType.ioProx ||
      t == TagType.idteck;

  @override
  Future<void> activateSlot(int slot) async {
    await _enter('activateSlot($slot)');
    activeSlot = slot;
  }

  @override
  Future<int> getActiveSlot() async {
    await _enter('getActiveSlot');
    return activeSlot;
  }

  @override
  Future<void> setSlotType(int slot, TagType type) async {
    await _enter('setSlotType($slot,${type.name})');
    if (_isLf(type)) {
      slots[slot].lfType = type;
    } else {
      slots[slot].hfType = type;
    }
  }

  @override
  Future<void> setDefaultDataToSlot(int slot, TagType type) async {
    await _enter('setDefaultDataToSlot($slot,${type.name})');
    slots[slot].reset();
  }

  @override
  Future<void> enableSlot(int slot, TagFrequency frequency, bool status) async {
    await _enter('enableSlot($slot,${frequency.name},$status)');
    if (frequency == TagFrequency.hf) {
      slots[slot].hfEnabled = status;
    } else {
      slots[slot].lfEnabled = status;
    }
  }

  @override
  Future<void> setSlotTagName(
    int index,
    String name,
    TagFrequency frequency,
  ) async {
    await _enter('setSlotTagName($index,${frequency.name})');
    if (frequency == TagFrequency.hf) {
      slots[index].hfName = name;
    } else {
      slots[index].lfName = name;
    }
  }

  @override
  Future<String> getSlotTagName(int index, TagFrequency frequency) async {
    await _enter('getSlotTagName($index)');
    return frequency == TagFrequency.hf
        ? slots[index].hfName
        : slots[index].lfName;
  }

  @override
  Future<List<SlotNames>> getSlotTagNames() async {
    await _enter('getSlotTagNames');
    return slots.map((s) => SlotNames(hf: s.hfName, lf: s.lfName)).toList();
  }

  @override
  Future<List<SlotTypes>> getSlotTagTypes() async {
    await _enter('getSlotTagTypes');
    return slots.map((s) => SlotTypes(hf: s.hfType, lf: s.lfType)).toList();
  }

  @override
  Future<List<EnabledSlotInfo>> getEnabledSlots() async {
    await _enter('getEnabledSlots');
    return slots
        .map((s) => EnabledSlotInfo(hf: s.hfEnabled, lf: s.lfEnabled))
        .toList();
  }

  @override
  Future<void> saveSlotData() async {
    await _enter('saveSlotData');
    saved = true;
  }

  @override
  Future<void> setMf1AntiCollision(CardData card) async {
    await _enter('setMf1AntiCollision');
    slots[activeSlot].antiCollision = card;
  }

  @override
  Future<void> setMf1BlockData(int startBlock, Uint8List blocks) async {
    await _enter('setMf1BlockData($startBlock,${blocks.length})');
    for (var i = 0; i * 16 < blocks.length; i++) {
      slots[activeSlot].blocks[startBlock + i] = Uint8List.fromList(
        blocks.sublist(i * 16, i * 16 + 16),
      );
    }
  }

  @override
  Future<void> mf0EmulatorWritePages(int from, Uint8List data) async {
    await _enter('mf0EmulatorWritePages($from)');
    for (var i = 0; i * 4 < data.length; i++) {
      slots[activeSlot].pages[from + i] = Uint8List.fromList(
        data.sublist(i * 4, i * 4 + 4),
      );
    }
  }

  @override
  Future<void> mf0EmulatorSetVersionData(Uint8List data) async {
    await _enter('mf0EmulatorSetVersionData');
    slots[activeSlot].mfuVersion = data;
  }

  @override
  Future<void> mf0EmulatorSetSignatureData(Uint8List data) async {
    await _enter('mf0EmulatorSetSignatureData');
    slots[activeSlot].mfuSignature = data;
  }

  @override
  Future<void> mf0EmulatorSetCounterData(
    int index,
    int value,
    bool resetTearing,
  ) async {
    await _enter('mf0EmulatorSetCounterData($index)');
    slots[activeSlot].mfuCounters[index] = value;
  }

  @override
  Future<int> mf0ResetAuthCount() async {
    await _enter('mf0ResetAuthCount');
    return 0;
  }

  Future<void> _setLfId(TagType type, Uint8List uid) async {
    await _enter('set${type.name}EmulatorID');
    slots[activeSlot].lfIds[type] = uid;
  }

  @override
  Future<void> setEM410XEmulatorID(Uint8List uid) =>
      _setLfId(TagType.em410X, uid);

  @override
  Future<void> setHIDProxEmulatorID(Uint8List uid) =>
      _setLfId(TagType.hidProx, uid);

  @override
  Future<void> setVikingEmulatorID(Uint8List uid) =>
      _setLfId(TagType.viking, uid);

  @override
  Future<void> setPacEmulatorID(Uint8List uid) => _setLfId(TagType.pac, uid);

  @override
  Future<void> setIoProxEmulatorID(Uint8List uid) =>
      _setLfId(TagType.ioProx, uid);

  @override
  Future<void> setIdteckEmulatorID(Uint8List uid) =>
      _setLfId(TagType.idteck, uid);

  /// Unused by flows today but handy in assertions.
  String slotNameUtf8(int slot) => utf8.decode(utf8.encode(slots[slot].hfName));
}
