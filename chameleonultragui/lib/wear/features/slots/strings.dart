import 'package:chameleonultragui/helpers/definitions.dart';

/// English strings of the Slots feature (kept out of the .arb files).
class SlotStrings {
  SlotStrings._();

  static const title = 'Slots';
  static const empty = 'Empty';
  static const active = 'Active';
  static const inUse = 'In use';
  static const loadFailed = 'Could not read slots';
  static const retry = 'Retry';
  static const activate = 'Activate';
  static const activated = 'Slot activated';
  static const settings = 'Settings';
  static const enabled = 'Enabled';
  static const hf = 'HF';
  static const lf = 'LF';
  static const rename = 'Rename';
  static const save = 'Save';
  static const saved = 'Saved';
  static const noName = 'No name';
  static const nameLabel = 'Name';
  static const clear = 'Clear';
  static const cleared = 'Cleared';
  static const settingsReading = 'Reading settings';
  static const settingsLoadFailed = 'Could not read settings';
  static const noSettings = 'No options for this tag type';
  static const settingsActivates = 'Opens on the active slot';
  static const phoneOnly = 'UID, ATQA, SAK and keys: edit in the phone app';
  static const gen1a = 'Gen1a magic';
  static const gen2 = 'Gen2 magic';
  static const uidMagic = 'UID magic';
  static const block0Anticoll = 'Block 0 anticoll';
  static const detection = 'Detect nonces';
  static const prng = 'PRNG';
  static const writeMode = 'Write mode';
  static const readOnlyUid = 'UID';
  static const readOnlyAtqa = 'ATQA';
  static const readOnlySak = 'SAK';

  static String slot(int index) => 'Slot ${index + 1}';
  static String openSlot(int index) => 'Open slot ${index + 1}';
  static String failed(Object e) {
    var s = e.toString().replaceFirst(RegExp(r'^(Exception|Error): '), '');
    if (s.length > 48) s = '${s.substring(0, 45)}...';
    return 'Failed: $s';
  }

  static String clearTitle(String freq) => 'Clear $freq data?';
  static const clearMessage = 'Removes this tag from the slot.';

  static String writeModeLabel(MifareWriteMode m) => switch (m) {
    MifareWriteMode.normal => 'Normal',
    MifareWriteMode.denied => 'Decline',
    MifareWriteMode.deceive => 'Deceive',
    MifareWriteMode.shadow => 'Shadow',
  };

  static String prngLabel(Mf1PrngType t) => switch (t) {
    Mf1PrngType.static => 'Static',
    Mf1PrngType.weak => 'Weak',
    Mf1PrngType.hard => 'Hard',
  };

  /// Short tag type label that fits next to an HF/LF prefix.
  static String tagLabel(TagType t) => switch (t) {
    TagType.unknown => empty,
    TagType.em410X ||
    TagType.em410X16 ||
    TagType.em410X32 ||
    TagType.em410X64 ||
    TagType.em410XElectra => 'EM410X',
    TagType.pac => 'PAC',
    TagType.viking => 'Viking',
    TagType.hidProx => 'HID Prox',
    TagType.ioProx => 'IoProx',
    TagType.idteck => 'Idteck',
    TagType.mifareMini => 'MIFARE Mini',
    TagType.mifare1K => 'MIFARE 1K',
    TagType.mifare2K => 'MIFARE 2K',
    TagType.mifare4K => 'MIFARE 4K',
    TagType.ntag210 => 'NTAG210',
    TagType.ntag212 => 'NTAG212',
    TagType.ntag213 => 'NTAG213',
    TagType.ntag215 => 'NTAG215',
    TagType.ntag216 => 'NTAG216',
    TagType.ultralight => 'Ultralight',
    TagType.ultralightC => 'Ultralight C',
    TagType.ultralight11 => 'Ultralight EV1',
    TagType.ultralight21 => 'Ultralight EV1',
    TagType.hf14a4 => 'ISO 14443-4',
  };
}
