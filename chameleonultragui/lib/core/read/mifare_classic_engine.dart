import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/core/read/key_recovery_backend.dart';
import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/recovery/recovery.dart'
    show
        DarksideDart,
        DarksideItemDart,
        HardNestedDart,
        NestedDart,
        StaticEncryptedNestedDart,
        StaticNestedDart;
import 'package:logger/logger.dart';

/// Thrown from engine checkpoints when the owning session was cancelled.
class ReadCancelledSignal implements Exception {
  const ReadCancelledSignal();
}

/// A key recovery step ended without an exception but cannot continue.
class EngineFailure {
  final ReadErrorCode code;
  final String? detail;

  const EngineFailure(this.code, {this.detail});
}

/// [EngineFailure.detail] used when the card returned no hardnested nonces.
const kReadDetailFirmwareTooOld = 'firmware_too_old';

extension PartitionList<E> on List<E> {
  List<List<E>> partition(int size) {
    assert(size > 0);
    final out = <List<E>>[];
    for (var i = 0; i < length; i += size) {
      final end = i + size < length ? i + size : length;
      out.add(sublist(i, end));
    }
    return out;
  }
}

/// Result of probing a Mifare Classic card (no key checking).
class MifareClassicIdentity {
  final MifareClassicType type;
  final bool isEV1;
  final NTLevel ntLevel;
  final bool hasBackdoor;

  const MifareClassicIdentity({
    required this.type,
    required this.isEV1,
    required this.ntLevel,
    required this.hasBackdoor,
  });
}

/// Extracted from `performMifareClassicScan` (same command order).
Future<MifareClassicIdentity> identifyMifareClassic(
  ChameleonCommunicator communicator, {
  TagType? override,
}) async {
  MifareClassicType type;
  if (override != null) {
    type = chameleonTagTypeGetMfClassicType(override);
  } else {
    type = await mfClassicGetType(communicator);
  }

  NTLevel ntLevel = NTLevel.unknown;

  bool isEV1 = await communicator.mf1Auth(0x45, 0x61, gMifareClassicKeys[3]);

  try {
    ntLevel = await communicator.getMf1NTLevel();
  } catch (_) {}

  bool hasBackdoor = await mfClassicHasBackdoor(communicator);

  return MifareClassicIdentity(
    type: type,
    isEV1: isEV1,
    ntLevel: ntLevel,
    hasBackdoor: hasBackdoor,
  );
}

/// Headless Mifare Classic key check / recovery / dump. Extracted from the
/// phone's `MifareClassicRecovery`; it never touches localization, Provider or
/// BuildContext. Progress goes out as typed [ReadEvent]s through [emit] and as
/// in-place mutation of [checkMarks] / [validKeys] / [cardData], after which
/// [changed] is called (the phone's old `update()`).
///
/// The lists use the phone layout: index = sector + keyType * 40 (length 80
/// for [checkMarks] and [validKeys], 256 for [cardData]). Emitted events use
/// the contract layout (sector * 2 + keyType).
class MifareClassicEngine {
  final ChameleonCommunicator communicator;
  final KeyRecoveryBackend backend;
  final Logger? log;

  /// Keys per `mf1AuthMultipleKeys` command (BLE 32, USB 64).
  final int keyChunkSize;
  final bool allowHardnested;
  final void Function(ReadEvent event) emit;
  final void Function() changed;
  final bool Function() isCancelled;

  MifareClassicType type;
  bool isEV1;
  bool allKeysExists;
  final List<SectorKeyState> checkMarks;
  final List<Uint8List> validKeys;
  List<Uint8List> cardData;

  MifareClassicEngine({
    required this.communicator,
    required this.backend,
    required this.type,
    required this.isEV1,
    required this.checkMarks,
    required this.validKeys,
    required this.cardData,
    required this.keyChunkSize,
    this.log,
    this.allowHardnested = true,
    this.allKeysExists = false,
    void Function(ReadEvent event)? emit,
    void Function()? changed,
    bool Function()? isCancelled,
  }) : emit = emit ?? ((_) {}),
       changed = changed ?? (() {}),
       isCancelled = isCancelled ?? (() => false);

  /// Fresh 80-entry state lists.
  static List<SectorKeyState> newCheckMarks() =>
      List.generate(80, (_) => SectorKeyState.none);

  static List<Uint8List> newKeys() => List.generate(80, (_) => Uint8List(0));

  static List<Uint8List> newCardData() =>
      List.generate(256, (_) => Uint8List(0));

  /// Pre-fills the well-known EV1 signature sector keys.
  static void applyEv1Keys(
    List<SectorKeyState> checkMarks,
    List<Uint8List> validKeys,
    bool isEV1, {
    void Function()? changed,
  }) {
    if (!isEV1) return;
    void found(int sector, int keyType, Uint8List key) {
      checkMarks[sector + (keyType * 40)] = SectorKeyState.found;
      validKeys[sector + (keyType * 40)] = key;
      changed?.call();
    }

    found(16, 0, gMifareClassicKeys[4]); // MFC EV1 SIGNATURE 16 A
    found(16, 1, gMifareClassicKeys[5]); // MFC EV1 SIGNATURE 16 B
    found(17, 0, gMifareClassicKeys[6]); // MFC EV1 SIGNATURE 17 A
    found(17, 1, gMifareClassicKeys[3]); // MFC EV1 SIGNATURE 17 B
  }

  void _cp() {
    if (isCancelled()) throw const ReadCancelledSignal();
  }

  int get _sectorCount => mfClassicGetSectorCount(type, isEV1: isEV1);

  void initializeEV1() =>
      applyEv1Keys(checkMarks, validKeys, isEV1, changed: changed);

  // ---- state helpers ------------------------------------------------------

  Uint8List getSectorKey(int sector, int keyType) =>
      validKeys[sector + (keyType * 40)];

  SectorKeyState getSectorState(int sector, int keyType) =>
      checkMarks[sector + (keyType * 40)];

  bool _resolved(int sector, int keyType) {
    final s = getSectorState(sector, keyType);
    return s == SectorKeyState.found || s == SectorKeyState.disabled;
  }

  void setKeyAsFound(int sector, int keyType, Uint8List key) {
    checkMarks[sector + (keyType * 40)] = SectorKeyState.found;
    validKeys[sector + (keyType * 40)] = key;
    changed();
  }

  void setCheckingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == SectorKeyState.none) {
      checkMarks[sector + (keyType * 40)] = SectorKeyState.checking;
    }
    changed();
  }

  void setMissingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == SectorKeyState.checking) {
      checkMarks[sector + (keyType * 40)] = SectorKeyState.none;
      changed();
    }
  }

  List<SectorKeyState> _snapshot() {
    final out = List<SectorKeyState>.filled(80, SectorKeyState.none);
    for (var sector = 0; sector < 40; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        out[sector * 2 + keyType] = checkMarks[sector + keyType * 40];
      }
    }
    return out;
  }

  int _sectorsDone() {
    var done = 0;
    for (var sector = 0; sector < _sectorCount; sector++) {
      if (_resolved(sector, 0) && _resolved(sector, 1)) done++;
    }
    return done;
  }

  int _keysFound() =>
      checkMarks.where((state) => state == SectorKeyState.found).length;

  void _emitChecking(
    int sector,
    int keyType,
    int keyCount,
    int chunksDone,
    int chunksTotal,
  ) {
    emit(
      ReadCheckingKeys(
        sector: sector,
        keyType: keyType,
        keyCount: keyCount,
        chunksDone: chunksDone,
        chunksTotal: chunksTotal,
        sectorsDone: _sectorsDone(),
        sectorsTotal: _sectorCount,
        sectorStates: _snapshot(),
      ),
    );
  }

  void _emitRecovery(
    RecoveryAttack attack,
    RecoveryStep step, {
    int? sector,
    int? keyType,
    double? progress,
    bool viaBackdoor = false,
  }) {
    emit(
      ReadRecoveryProgress(
        attack: attack,
        step: step,
        sector: sector,
        keyType: keyType,
        progress: progress,
        keysFound: _keysFound(),
        viaBackdoor: viaBackdoor,
      ),
    );
  }

  bool _computeAllKeysExist() {
    for (var sector = 0; sector < _sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (!_resolved(sector, keyType)) return false;
      }
    }
    return true;
  }

  // ---- key check ----------------------------------------------------------

  Future<bool> checkKeysOnSector(
    List<Uint8List> keys,
    int keyType,
    int sector,
  ) async {
    Uint8List? key;
    final chunks = keys.partition(keyChunkSize);
    final totalChunks = chunks.length;
    _emitChecking(sector, keyType, keys.length, 0, totalChunks);

    if (!_resolved(sector, keyType)) {
      setCheckingSector(sector, keyType);

      for (var i = 0; i < chunks.length; i++) {
        _cp();
        key = await communicator.mf1AuthMultipleKeys(
          mfClassicGetSectorTrailerBlockBySector(sector),
          0x60 + keyType,
          chunks[i],
        );
        if (key != null) {
          setKeyAsFound(sector, keyType, key);
          _emitChecking(sector, keyType, keys.length, 0, totalChunks);
          await recheckKey(key, sector);
          return true;
        } else if (totalChunks > 10) {
          _emitChecking(sector, keyType, keys.length, i + 1, totalChunks);
          changed();
        }
      }

      if (key == null) {
        setMissingSector(sector, keyType);
      }
    }

    setMissingSector(sector, keyType);
    _emitChecking(sector, keyType, keys.length, 0, totalChunks);
    return false;
  }

  Future<void> recheckKey(Uint8List key, int startingSector) async {
    for (var sector = startingSector; sector < _sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == SectorKeyState.none) {
          _cp();
          _emitChecking(sector, keyType, 1, 0, 1);
          log?.d(
            "Checking found key ${bytesToHex(key)} on sector $sector, key type $keyType",
          );
          setCheckingSector(sector, keyType);

          if (await communicator.mf1Auth(
            mfClassicGetSectorTrailerBlockBySector(sector),
            0x60 + keyType,
            key,
          )) {
            // Found valid key
            setKeyAsFound(sector, keyType, key);
          } else {
            setMissingSector(sector, keyType);
          }

          changed();
        }
      }
    }
  }

  /// [keys] is the full candidate list (user dictionary first, then the
  /// built-in defaults unless the caller leaves them out).
  Future<void> checkKeys(List<Uint8List> keys) async {
    initializeEV1();

    for (var sector = 0; sector < _sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        await checkKeysOnSector(keys, keyType, sector);
      }
    }

    // Key check part competed, checking found keys
    allKeysExists = _computeAllKeysExist();
    changed();
  }

  // ---- recovery -----------------------------------------------------------

  /// Returns null on completion, or the reason the recovery gave up.
  Future<EngineFailure?> recoverKeys() async {
    _emitRecovery(RecoveryAttack.detecting, RecoveryStep.collectingNonces);
    changed();

    bool hasKey = false;
    _cp();
    bool hasBackdoor = await mfClassicHasBackdoor(communicator);
    (int, NestedNonces, NestedNonces, Uint8List)? backdoorInfo;
    if (hasBackdoor) {
      _cp();
      backdoorInfo = await communicator.getMf1StaticEncryptedNestedAcquire(
        sectorCount: _sectorCount,
      );
    }

    DarksideResult darkside = DarksideResult.fixed;
    for (var sector = 0; sector < _sectorCount && !hasKey; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == SectorKeyState.found) {
          hasKey = true;
          break;
        }
      }
    }

    changed();

    bool isStaticEncrypted = false;

    if (hasBackdoor) {
      _cp();
      isStaticEncrypted = await mfClassicIsStaticEncrypted(
        communicator,
        0,
        4,
        backdoorInfo!.$4,
      );
    }

    _cp();
    NTLevel prng = await communicator.getMf1NTLevel();
    changed();

    if (!hasKey && !isStaticEncrypted && prng != NTLevel.static) {
      _emitRecovery(
        RecoveryAttack.darkside,
        RecoveryStep.collectingNonces,
        sector: 0,
        keyType: 1,
      );
      changed();

      try {
        setCheckingSector(0, 1);
        _cp();
        darkside = await communicator.checkMf1Darkside();
      } on ReadCancelledSignal {
        rethrow;
      } catch (_) {
        setMissingSector(0, 1);
      }

      if (darkside == DarksideResult.vulnerable) {
        // recover with darkside
        _cp();
        var data = await communicator.getMf1Darkside(0x03, 0x61, true, 15);
        var darksideInput = DarksideDart(uid: data.uid, items: []);
        bool found = false;
        changed();

        for (var tries = 0; tries < 5 && !found; tries++) {
          darksideInput.items.add(
            DarksideItemDart(
              nt1: data.nt1,
              ks1: data.ks1,
              par: data.par,
              nr: data.nr,
              ar: data.ar,
            ),
          );

          _emitRecovery(
            RecoveryAttack.darkside,
            RecoveryStep.recoveringKey,
            sector: 0,
            keyType: 1,
          );
          var keys = await backend.darkside(darksideInput);
          if (keys.isNotEmpty) {
            log?.d("Darkside: Found keys: $keys. Checking them...");

            if (await checkKeysOnSector(mfClassicConvertKeys(keys), 1, 0)) {
              found = true;
              hasKey = true;

              break;
            }
          } else {
            log?.d("Can't find keys, retrying...");
            _cp();
            data = await communicator.getMf1Darkside(0x03, 0x61, false, 15);
          }
        }

        if (!found) {
          setMissingSector(0, 1);
        }
      }
    }

    changed();

    if (!hasKey && hasBackdoor && prng == NTLevel.weak && !isStaticEncrypted) {
      _emitRecovery(
        RecoveryAttack.nested,
        RecoveryStep.collectingNonces,
        sector: 0,
        keyType: 0,
        viaBackdoor: true,
      );
      setCheckingSector(0, 0);

      for (var i = 0; i < 3; i++) {
        _cp();
        NTDistance distance = await communicator.getMf1NTDistance(
          0,
          0x64,
          backdoorInfo!.$4,
        );

        NestedNonces nonces = await communicator.getMf1NestedNonces(
          0,
          0x64,
          backdoorInfo.$4,
          0,
          0x60,
          level: prng,
        );

        var nested = NestedDart(
          uid: distance.uid,
          distance: distance.distance,
          nt0: nonces.nonces[0].nt,
          nt0Enc: nonces.nonces[0].ntEnc,
          par0: nonces.nonces[0].parity,
          nt1: nonces.nonces[1].nt,
          nt1Enc: nonces.nonces[1].ntEnc,
          par1: nonces.nonces[1].parity,
        );

        List<int> keys = await backend.nested(nested);

        if (keys.isNotEmpty) {
          log?.d("Found keys: $keys. Checking them...");
          if (await checkKeysOnSector(mfClassicConvertKeys(keys), 0, 0)) {
            break;
          }
        }
      }
    }

    Uint8List validKey = Uint8List(0);
    int validKeyBlock = 0;
    int validKeyType = -1;

    for (var sector = 0; sector < _sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == SectorKeyState.found) {
          validKey = getSectorKey(sector, keyType);
          validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
          validKeyType = keyType;
          if (!isStaticEncrypted) {
            _cp();
            isStaticEncrypted = await mfClassicIsStaticEncrypted(
              communicator,
              validKeyBlock,
              validKeyType,
              validKey,
            );
          }
          break;
        }
      }
    }

    if ((isStaticEncrypted || (validKeyType == -1 && hasBackdoor)) &&
        backdoorInfo != null) {
      prng = NTLevel.backdoor;
    }

    if (validKeyType == -1 && prng != NTLevel.backdoor) {
      return const EngineFailure(ReadErrorCode.noKeysForRecovery);
    }

    int tries = [NTLevel.backdoor, NTLevel.static].contains(prng) ? 1 : 5;

    final RecoveryAttack attack = switch (prng) {
      NTLevel.static => RecoveryAttack.staticNested,
      NTLevel.weak => RecoveryAttack.nested,
      NTLevel.hard => RecoveryAttack.hardnested,
      NTLevel.backdoor => RecoveryAttack.backdoor,
      NTLevel.unknown => RecoveryAttack.detecting,
    };

    for (var sector = 0; sector < _sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == SectorKeyState.none) {
          if (prng == NTLevel.hard && !allowHardnested) {
            return const EngineFailure(ReadErrorCode.hardnestedUnavailable);
          }

          _emitRecovery(
            attack,
            RecoveryStep.collectingNonces,
            sector: sector,
            keyType: keyType,
          );
          setCheckingSector(sector, keyType);

          NTDistance? distance;
          NestedNonces? nonces;

          if (prng != NTLevel.backdoor) {
            _cp();
            distance = await communicator.getMf1NTDistance(
              validKeyBlock,
              0x60 + validKeyType,
              validKey,
            );
          }

          bool found = false;
          for (var i = 0; i < tries && !found; i++) {
            List<int> keys = [];

            if (prng == NTLevel.hard) {
              changed();

              var result = await collectHardnestedNonces(
                validKeyBlock,
                0x60 + validKeyType,
                validKey,
                mfClassicGetSectorTrailerBlockBySector(sector),
                0x60 + keyType,
                sector,
                keyType,
              );

              if (result is EngineFailure) {
                setMissingSector(sector, keyType);
                return result;
              } else {
                nonces = result as NestedNonces;
              }
            } else if (prng != NTLevel.backdoor) {
              _cp();
              nonces = await communicator.getMf1NestedNonces(
                validKeyBlock,
                0x60 + validKeyType,
                validKey,
                mfClassicGetSectorTrailerBlockBySector(sector),
                0x60 + keyType,
                level: prng,
              );
            }

            _emitRecovery(
              attack,
              RecoveryStep.recoveringKey,
              sector: sector,
              keyType: keyType,
            );
            changed();
            _cp();

            if (prng == NTLevel.weak) {
              var nested = NestedDart(
                uid: distance!.uid,
                distance: distance.distance,
                nt0: nonces!.nonces[0].nt,
                nt0Enc: nonces.nonces[0].ntEnc,
                par0: nonces.nonces[0].parity,
                nt1: nonces.nonces[1].nt,
                nt1Enc: nonces.nonces[1].ntEnc,
                par1: nonces.nonces[1].parity,
              );

              keys = await backend.nested(nested);
            } else if (prng == NTLevel.static) {
              var nested = StaticNestedDart(
                uid: distance!.uid,
                keyType: 0x60 + validKeyType,
                nt0: nonces!.nonces[0].nt,
                nt0Enc: nonces.nonces[0].ntEnc,
                nt1: nonces.nonces[1].nt,
                nt1Enc: nonces.nonces[1].ntEnc,
              );

              keys = await backend.staticNested(nested);
            } else if (prng == NTLevel.hard) {
              var nested = HardNestedDart(
                nonces: nonces!.getHardNested(distance!.uid),
              );
              keys = await backend.hardnested(nested);
            } else if (prng == NTLevel.backdoor) {
              setCheckingSector(sector, 1);

              var possibleAKeys = await backend.staticEncryptedNested(
                StaticEncryptedNestedDart(
                  uid: backdoorInfo!.$1,
                  nt: backdoorInfo.$2.nonces[sector].nt,
                  ntEnc: backdoorInfo.$2.nonces[sector].ntEnc,
                  ntParEnc: backdoorInfo.$2.nonces[sector].parity,
                ),
              );

              var possibleBKeys = await backend.staticEncryptedNested(
                StaticEncryptedNestedDart(
                  uid: backdoorInfo.$1,
                  nt: backdoorInfo.$3.nonces[sector].nt,
                  ntEnc: backdoorInfo.$3.nonces[sector].ntEnc,
                  ntParEnc: backdoorInfo.$3.nonces[sector].parity,
                ),
              );

              var filtered = await StaticEncryptedKeysFilterAsync.filterKeys(
                possibleAKeys,
                possibleBKeys,
                backdoorInfo.$2.nonces[sector].nt,
                backdoorInfo.$3.nonces[sector].nt,
              );

              if (checkMarks[sector + 40] != SectorKeyState.found &&
                  checkMarks[sector + 40] != SectorKeyState.disabled &&
                  await checkKeysOnSector(
                    mfClassicConvertKeys(filtered.$2.reversed.toList()),
                    1,
                    sector,
                  )) {
                checkMarks[sector + 40] = SectorKeyState.found;
              }

              if (checkMarks[sector] == SectorKeyState.found ||
                  checkMarks[sector] == SectorKeyState.disabled) {
                found = true;
                break;
              } else if (await checkKeysOnSector(
                mfClassicConvertKeys(
                  await StaticEncryptedKeysFilterAsync.findMatchingKeys(
                    backdoorInfo.$3.nonces[sector].nt,
                    bytesToU64(
                      Uint8List.fromList([0, 0, ...validKeys[sector + 40]]),
                    ),
                    backdoorInfo.$2.nonces[sector].nt,
                    possibleAKeys,
                  ),
                ),
                0,
                sector,
              )) {
                found = true;
                break;
              } else if (await checkKeysOnSector(
                mfClassicConvertKeys(filtered.$1.reversed.toList()),
                0,
                sector,
              )) {
                found = true;
                break;
              }

              setMissingSector(sector, 0);
              setMissingSector(sector, 1);
            }

            if (keys.isNotEmpty) {
              log?.d("Found keys: $keys. Checking them...");

              if (await checkKeysOnSector(
                mfClassicConvertKeys(keys),
                keyType,
                sector,
              )) {
                found = true;

                break;
              }
            } else {
              log?.e("Can't find keys, retrying...");
            }
          }
        }
      }
    }

    allKeysExists = _computeAllKeysExist();
    changed();
    return null;
  }

  /// Returns [NestedNonces], or an [EngineFailure] when the device sent none.
  Future<Object> collectHardnestedNonces(
    int block,
    int keyType,
    Uint8List knownKey,
    int targetBlock,
    int targetKeyType,
    int sector,
    int sectorKeyType,
  ) async {
    NestedNonces nonces = NestedNonces(nonces: []);
    _emitRecovery(
      RecoveryAttack.hardnested,
      RecoveryStep.collectingNonces,
      sector: sector,
      keyType: sectorKeyType,
      progress: 0,
    );
    while (true) {
      _cp();
      var collectedNonces = await communicator.getMf1NestedNonces(
        block,
        keyType,
        knownKey,
        targetBlock,
        targetKeyType,
        level: NTLevel.hard,
      );
      nonces.nonces.addAll(collectedNonces.nonces);
      List info = nonces.getNoncesInfo();
      log?.d(
        "Collected ${nonces.nonces.length} nonces, sum ${info[0]}, num ${info[1]}",
      );

      if (nonces.nonces.isEmpty) {
        return const EngineFailure(
          ReadErrorCode.recoveryFailed,
          detail: kReadDetailFirmwareTooOld,
        );
      }

      _emitRecovery(
        RecoveryAttack.hardnested,
        RecoveryStep.collectingNonces,
        sector: sector,
        keyType: sectorKeyType,
        progress: info[1] / 256,
      );
      changed();
      if (info[1] == 256) {
        if ([
          0,
          32,
          56,
          64,
          80,
          96,
          104,
          112,
          120,
          128,
          136,
          144,
          152,
          160,
          176,
          192,
          200,
          224,
          256,
        ].contains(info[0])) {
          break;
        }

        log?.e("Got wrong sum, trying to collect nonces again...");
        nonces.nonces = [];
      }
    }

    return nonces;
  }

  // ---- dump ---------------------------------------------------------------

  Future<void> dumpData() async {
    cardData = newCardData();

    for (var sector = 0; sector < _sectorCount; sector++) {
      for (
        var block = 0;
        block < mfClassicGetBlockCountBySector(sector);
        block++
      ) {
        for (var keyType = 0; keyType < 2; keyType++) {
          log?.d("Dumping sector $sector, block $block with key $keyType");

          if (getSectorKey(sector, keyType).isEmpty) {
            log?.w("Skipping missing key");
            cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
                Uint8List(16);
            continue;
          }

          _cp();
          var blockData = await communicator.mf1ReadBlock(
            block + mfClassicGetFirstBlockCountBySector(sector),
            0x60 + keyType,
            getSectorKey(sector, keyType),
          );

          if (blockData.isEmpty) {
            if (keyType == 1) {
              blockData = Uint8List(16);
            } else {
              continue;
            }
          }

          if (mfClassicGetSectorTrailerBlockBySector(sector) ==
              block + mfClassicGetFirstBlockCountBySector(sector)) {
            // set keys in sector trailer
            if (getSectorKey(sector, 0).isNotEmpty) {
              blockData.setRange(0, 6, getSectorKey(sector, 0));
            }

            if (getSectorKey(sector, 1).isNotEmpty) {
              blockData.setRange(10, 16, getSectorKey(sector, 1));
            }
          }

          cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
              blockData;

          emit(
            ReadDumpProgress(
              block + mfClassicGetFirstBlockCountBySector(sector),
              mfClassicGetBlockCount(type, isEV1: isEV1),
            ),
          );

          changed();

          break;
        }
      }
    }
  }
}
