import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/core/read/key_recovery_backend.dart';
import 'package:chameleonultragui/core/read/mifare_classic_engine.dart';
import 'package:chameleonultragui/core/read/native_key_recovery_backend.dart';
import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

/// Same four states as the headless [SectorKeyState].
typedef ChameleonKeyCheckmark = SectorKeyState;

/// Phone-side adapter around the headless [MifareClassicEngine]: keeps the
/// fields the widgets read (`state`, `error`, `checkMarks`, ...) and renders
/// the engine's typed events with the app's localized strings.
class MifareClassicRecovery {
  late ChameleonGUIState appState;
  late AppLocalizations localizations;
  String error;
  String state;
  bool allKeysExists;
  List<Dictionary> dictionaries;
  Dictionary? selectedDictionary;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;
  List<Uint8List> cardData;
  double dumpProgress;
  double? hardnestedProgress;
  double? keyCheckProgress;
  void Function() update;
  MifareClassicType mifareClassicType;
  bool isMifareClassicEV1;
  final KeyRecoveryBackend backend;

  MifareClassicRecovery(
      {required this.appState,
      required this.update,
      required this.localizations,
      this.error = '',
      this.state = '',
      this.allKeysExists = false,
      this.dictionaries = const [],
      this.dumpProgress = 0,
      this.selectedDictionary,
      this.mifareClassicType = MifareClassicType.none,
      this.isMifareClassicEV1 = false,
      this.backend = const NativeKeyRecoveryBackend(),
      List<ChameleonKeyCheckmark>? checkMarks,
      List<Uint8List>? validKeys,
      List<Uint8List>? cardData})
      : checkMarks = checkMarks ?? MifareClassicEngine.newCheckMarks(),
        validKeys = validKeys ?? MifareClassicEngine.newKeys(),
        cardData = cardData ?? MifareClassicEngine.newCardData() {
    initializeEV1();
  }

  MifareClassicEngine _engine() => MifareClassicEngine(
        communicator: appState.communicator!,
        backend: backend,
        log: appState.log,
        type: mifareClassicType,
        isEV1: isMifareClassicEV1,
        keyChunkSize:
            appState.connector!.connectionType == ConnectionType.ble ? 32 : 64,
        checkMarks: checkMarks,
        validKeys: validKeys,
        cardData: cardData,
        allKeysExists: allKeysExists,
        emit: _onEvent,
        changed: update,
      );

  void _onEvent(ReadEvent event) {
    if (event is ReadCheckingKeys) {
      state = localizations.checking_keys(event.keyCount);
      keyCheckProgress = (event.chunksTotal > 10 && event.chunksDone > 0)
          ? event.chunksDone / event.chunksTotal
          : null;
    } else if (event is ReadRecoveryProgress) {
      _onRecoveryProgress(event);
    } else if (event is ReadDumpProgress) {
      dumpProgress = event.blocksDone / event.blocksTotal;
    }
  }

  void _onRecoveryProgress(ReadRecoveryProgress event) {
    if (event.attack == RecoveryAttack.detecting && event.sector == null) {
      state = localizations.checking_card_info;
      return;
    }

    if (event.attack == RecoveryAttack.darkside) {
      state = localizations.checking_or_running_darkside;
      return;
    }

    if (event.viaBackdoor) {
      state = localizations.backdoor_recovery_of_non_static_encrypted;
      return;
    }

    if (event.attack == RecoveryAttack.hardnested &&
        event.step == RecoveryStep.collectingNonces &&
        event.progress != null) {
      hardnestedProgress = event.progress;
      if (event.progress! > 0) {
        state = localizations.hardnested_collecting_nonces(
            (event.progress! * 256).toInt().toString());
      }
      return;
    }

    String attackType;
    switch (event.attack) {
      case RecoveryAttack.staticNested:
        attackType = "Static Nested";
      case RecoveryAttack.nested:
        attackType = "Nested";
      case RecoveryAttack.hardnested:
        attackType = "Hard Nested";
      case RecoveryAttack.backdoor:
        attackType = localizations.has_backdoor_support;
      case RecoveryAttack.detecting:
      case RecoveryAttack.darkside:
        attackType = "";
    }

    if (event.step == RecoveryStep.recoveringKey) {
      if (event.attack == RecoveryAttack.hardnested) {
        hardnestedProgress = null;
      }
      state = localizations.recovering_key(attackType);
    } else {
      state = localizations.collecting_nonces(attackType);
    }
  }

  Future<void> initialize() async {
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    var mifare = await appState.communicator!.detectMf1Support();

    if (mifare) {
      mifareClassicType = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
    }

    isMifareClassicEV1 =
        await appState.communicator!.mf1Auth(0x45, 0x61, gMifareClassicKeys[3]);
    initializeEV1();
  }

  void initializeEV1() {
    MifareClassicEngine.applyEv1Keys(checkMarks, validKeys, isMifareClassicEV1,
        changed: update);
  }

  Future<void> checkKeys({bool skipDefaultDictionary = false}) async {
    final keyList = [
      ...selectedDictionary!.keys,
      if (!skipDefaultDictionary)
        ...gMifareClassicKeys
            .where((key) => !selectedDictionary!.keys.contains(key))
    ];

    final engine = _engine();
    await engine.checkKeys(keyList);
    allKeysExists = engine.allKeysExists;

    state = "";
    update();
  }

  Future<void> recoverKeys() async {
    error = "";

    final engine = _engine();
    final failure = await engine.recoverKeys();
    allKeysExists = engine.allKeysExists;

    if (failure != null) {
      switch (failure.code) {
        case ReadErrorCode.noKeysForRecovery:
          error = localizations.recovery_error_no_keys_darkside;
          state = "";
        case ReadErrorCode.hardnestedUnavailable:
          error = localizations.recovery_error_no_supported;
        default:
          error = localizations.recovery_old_firmware;
      }
      return;
    }

    state = "";
    update();
  }

  Future<void> dumpData() async {
    final engine = _engine();
    try {
      await engine.dumpData();
    } finally {
      cardData = engine.cardData;
    }
  }
}
