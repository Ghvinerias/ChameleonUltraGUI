import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';

/// User-facing English strings of the Read feature (the watch is English-only,
/// so they live here instead of the .arb files).
class ReadStrings {
  ReadStrings._();

  static const menuTitle = 'Read';
  static const readHf = 'Read HF';
  static const readLf = 'Read LF';
  static const scanHf = 'Scan HF (continuous)';
  static const scanLf = 'Scan LF (continuous)';
  static const scanHfShort = 'Scan HF';
  static const scanLfShort = 'Scan LF';

  static const preparing = 'Getting ready…';
  static const placeCard = 'Hold the card on the Chameleon';
  static const attemptPrefix = 'Attempt';
  static const cardFound = 'Card found';
  static const stop = 'Stop';
  static const cancel = 'Cancel';
  static const retry = 'Retry';
  static const scanAgain = 'Scan again';
  static const readAgain = 'Read again';
  static const back = 'Back';
  static const done = 'Done';

  static const noCardTitle = 'No card';
  static const noCardBody = 'Place a card on the Chameleon and try again.';
  static const cardLostTitle = 'Card lost';
  static const cardLostBody = 'The card moved away. Hold it steady and retry.';
  static const stoppedTitle = 'Stopped';
  static const timedOutTitle = 'No card found';
  static const timedOutBody = 'The scan ended after 5 minutes.';
  static const failedTitle = 'Read failed';

  static const checkKeys = 'Check keys';
  static const recoverKeys = 'Recover keys';
  static const dump = 'Dump';
  static const checkingKeys = 'Checking keys';
  static const recovering = 'Recovering keys';
  static const dumping = 'Dumping';
  static const detecting = 'Detecting attack…';
  static const viaBackdoor = 'via backdoor';

  static const saveToWatch = 'Save to watch';
  static const writeToSlot = 'Write to slot';
  static const saveTitle = 'Save card';
  static const nameLabel = 'Name';
  static const save = 'Save';
  static const saved = 'Saved';
  static const savedBody = 'The card is in Saved cards.';
  static const saveFailed = 'Could not save the card.';

  static const writeTitle = 'Write to slot';
  static const writing = 'Writing…';
  static const writeDone = 'Written';
  static const writeFailed = 'Write failed';
  static const noNameFallback = 'Card';
  static const overwriteTitle = 'Overwrite slot?';
  static const overwrite = 'Overwrite';
  static const slotPickerTitle = 'Choose slot';
  static const slotPickerConfirm = 'Write to';

  static const hardnestedNeedsPhone = 'Needs the phone app';
  static const hardnestedBody =
      'These keys need the hardnested attack, which only the phone app can run.';

  static const uid = 'UID';
  static const atqa = 'ATQA';
  static const sak = 'SAK';
  static const ats = 'ATS';
  static const type = 'Type';
  static const id = 'ID';
  static const none = 'none';
  static const version = 'Version';
  static const signature = 'Signature';
  static const yes = 'yes';
  static const no = 'no';
  static const keys = 'Keys';
  static const nt = 'PRNG';
  static const backdoor = 'Backdoor';
  static const ev1 = 'EV1';
  static const infoOnly = 'Info only: dump pages on the phone app.';
  static const unsupportedSave = 'This card type cannot be saved.';

  static String attempt(int n) => '$attemptPrefix $n';

  static String keysFound(int found, int total) => '$found/$total keys';

  static String sectorProgress(int done, int total) => 'Sector $done/$total';

  static String attackName(RecoveryAttack attack) => switch (attack) {
    RecoveryAttack.detecting => detecting,
    RecoveryAttack.darkside => 'Darkside',
    RecoveryAttack.nested => 'Nested',
    RecoveryAttack.staticNested => 'Static nested',
    RecoveryAttack.hardnested => 'Hardnested',
    RecoveryAttack.backdoor => 'Backdoor',
  };

  static String ntLevel(NTLevel? level) => switch (level) {
    NTLevel.static => 'static',
    NTLevel.weak => 'weak',
    NTLevel.hard => 'hard',
    NTLevel.backdoor => 'backdoor',
    _ => 'unknown',
  };

  /// Short, human description of a failed read.
  static (String title, String body) failure(ReadErrorCode code) =>
      switch (code) {
        ReadErrorCode.notConnected => (
          'Not connected',
          'Connect the Chameleon and try again.',
        ),
        ReadErrorCode.communication => (
          'Connection problem',
          'The Chameleon did not answer. Check the connection.',
        ),
        ReadErrorCode.cardLost => (cardLostTitle, cardLostBody),
        ReadErrorCode.unsupportedCard => (
          'Unsupported card',
          'This card type cannot be read here.',
        ),
        ReadErrorCode.noKeysForRecovery => (
          'No usable key',
          'No key is known to start recovery from.',
        ),
        ReadErrorCode.recoveryFailed => (
          'Recovery failed',
          'The attack could not find the keys.',
        ),
        ReadErrorCode.recoveryUnavailable => (
          'Recovery unavailable',
          'Key recovery is not available on this watch.',
        ),
        ReadErrorCode.dumpFailed => (
          'Dump failed',
          'Some blocks could not be read.',
        ),
        ReadErrorCode.timeout => ('Timed out', 'The operation took too long.'),
        ReadErrorCode.unknown => (failedTitle, 'Something went wrong.'),
        ReadErrorCode.hardnestedUnavailable => (
          hardnestedNeedsPhone,
          hardnestedBody,
        ),
      };

  static String slotFailure(SlotErrorCode code) => switch (code) {
    SlotErrorCode.notConnected => 'Not connected.',
    SlotErrorCode.communication => 'The Chameleon did not answer.',
    SlotErrorCode.unsupportedCardType => 'This card type cannot be written.',
    SlotErrorCode.invalidSlot => 'Invalid slot.',
    SlotErrorCode.cancelled => 'Cancelled. The slot may be incomplete.',
    SlotErrorCode.unknown => 'Something went wrong.',
  };
}
