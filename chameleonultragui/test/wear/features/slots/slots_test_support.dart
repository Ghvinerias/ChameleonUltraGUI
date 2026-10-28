import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';

import '../../../fakes/fake_chameleon_communicator.dart';

/// The shared fake plus the per-slot emulator option commands the slots
/// feature needs (the shared fake does not script them). State is per active
/// slot like the real device.
class SlotsFake extends FakeChameleonCommunicator {
  EmulatorSettings mf1 = EmulatorSettings(
    isDetectionEnabled: false,
    isGen1a: false,
    isGen2: true,
    isAntiColl: false,
    writeMode: MifareWriteMode.normal,
  );
  Mf1PrngType prng = Mf1PrngType.weak;
  EmulatorSettings mfu = EmulatorSettings(
    isDetectionEnabled: true,
    isGen1a: false,
    isGen2: false,
    isAntiColl: false,
    writeMode: MifareWriteMode.denied,
  );
  final List<String> writes = [];

  Future<void> _call(String call) async {
    callLog.add(call);
    final err = failNext.remove(call.split('(').first);
    if (err != null) throw err;
  }

  /// Fills slots: 0 MFC 1K (+EM410X), 2 NTAG215, 5 EM410X only.
  void seed() {
    slots[0]
      ..hfType = TagType.mifare1K
      ..hfEnabled = true
      ..hfName = 'Office'
      ..lfType = TagType.em410X
      ..lfEnabled = true
      ..lfName = 'Gate';
    slots[2]
      ..hfType = TagType.ntag215
      ..hfEnabled = true
      ..hfName = 'Tag';
    slots[5]
      ..lfType = TagType.em410X
      ..lfEnabled = false
      ..lfName = 'Fob';
    activeSlot = 2;
  }

  @override
  Future<void> deleteSlotInfo(int index, TagFrequency frequency) async {
    await _call('deleteSlotInfo($index,${frequency.name})');
    if (frequency == TagFrequency.hf) {
      slots[index].hfType = TagType.unknown;
    } else {
      slots[index].lfType = TagType.unknown;
    }
  }

  @override
  Future<EmulatorSettings> getMf1EmulatorSettings() async {
    await _call('getMf1EmulatorSettings');
    return EmulatorSettings(
      isDetectionEnabled: mf1.isDetectionEnabled,
      isGen1a: mf1.isGen1a,
      isGen2: mf1.isGen2,
      isAntiColl: mf1.isAntiColl,
      writeMode: mf1.writeMode,
    );
  }

  @override
  Future<Mf1PrngType> getMf1PrngType() async {
    await _call('getMf1PrngType');
    return prng;
  }

  @override
  Future<CardData> mf1GetAntiCollData() async {
    await _call('mf1GetAntiCollData');
    return CardData(
      uid: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
      sak: 8,
      atqa: Uint8List.fromList([0x00, 0x04]),
      ats: Uint8List(0),
    );
  }

  @override
  Future<void> setMf1Gen1aMode(bool v) async {
    await _call('setMf1Gen1aMode($v)');
    mf1.isGen1a = v;
  }

  @override
  Future<void> setMf1Gen2Mode(bool v) async {
    await _call('setMf1Gen2Mode($v)');
    mf1.isGen2 = v;
  }

  @override
  Future<void> setMf1UseFirstBlockColl(bool v) async {
    await _call('setMf1UseFirstBlockColl($v)');
    mf1.isAntiColl = v;
  }

  @override
  Future<void> setMf1DetectionStatus(bool v) async {
    await _call('setMf1DetectionStatus($v)');
    mf1.isDetectionEnabled = v;
  }

  @override
  Future<void> setMf1PrngType(Mf1PrngType t) async {
    await _call('setMf1PrngType(${t.name})');
    prng = t;
  }

  @override
  Future<void> setMf1WriteMode(MifareWriteMode m) async {
    await _call('setMf1WriteMode(${m.name})');
    mf1.writeMode = m;
  }

  @override
  Future<EmulatorSettings> mf0NtagGetEmulatorConfig() async {
    await _call('mf0NtagGetEmulatorConfig');
    return EmulatorSettings(
      isDetectionEnabled: mfu.isDetectionEnabled,
      isGen1a: false,
      isGen2: mfu.isGen2,
      isAntiColl: false,
      writeMode: mfu.writeMode,
    );
  }

  @override
  Future<void> mf0SetMagicMode(bool v) async {
    await _call('mf0SetMagicMode($v)');
    mfu.isGen2 = v;
  }

  @override
  Future<void> mf0NtagSetDetectionEnable(bool v) async {
    await _call('mf0NtagSetDetectionEnable($v)');
    mfu.isDetectionEnabled = v;
  }

  @override
  Future<void> mf0NtagSetWriteMode(MifareWriteMode m) async {
    await _call('mf0NtagSetWriteMode(${m.name})');
    mfu.writeMode = m;
  }
}
