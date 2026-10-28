import 'package:chameleonultragui/core/slots/slot_service.dart';

/// User-facing English strings of the Saved cards feature.
class SavedCardsStrings {
  SavedCardsStrings._();

  static const title = 'Saved cards';
  static const loadFailed = 'Could not load saved cards';
  static const retry = 'Retry';
  static const emptyTitle = 'No saved cards';
  static const emptyBody =
      'Read a card on the watch, or sync from the phone, and it shows up here.';
  static const unfiled = 'No folder';
  static const unnamed = 'Unnamed card';

  static const uid = 'UID';
  static const atqa = 'ATQA';
  static const sak = 'SAK';
  static const ats = 'ATS';
  static const type = 'Type';
  static const dump = 'Dump';
  static const folder = 'Folder';

  static const loadIntoSlot = 'Load into slot';
  static const rename = 'Rename';
  static const delete = 'Delete';
  static const cannotLoad = "This card type can't be loaded into a slot yet.";

  static const renameTitle = 'Rename card';
  static const nameHint = 'Card name';
  static const save = 'Save';

  static const deleteTitle = 'Delete card?';
  static String deleteBody(String name) =>
      '"$name" will be removed from the watch.';
  static const cancel = 'Cancel';

  static const pickSlotTitle = 'Load into slot';
  static const pickSlotConfirm = 'Load into';
  static String overwriteTitle(int slot) => 'Overwrite slot ${slot + 1}?';
  static String overwriteBody(String current) =>
      'The slot currently holds $current. It will be replaced.';
  static const overwrite = 'Overwrite';
  static const slotInUse = 'another card';
  static const checkingSlot = 'Checking slot…';

  static String uploading(int slot) => 'Writing slot ${slot + 1}';
  static String uploaded(int slot) => 'Loaded into slot ${slot + 1}';
  static const done = 'Done';
  static const close = 'Close';
  static const cancelUpload = 'Cancel';
  static const uploadCancelled = 'Cancelled. The slot may be partly written.';

  static String uploadError(SlotErrorCode code) => switch (code) {
    SlotErrorCode.notConnected => 'The Chameleon disconnected.',
    SlotErrorCode.communication => 'Lost contact with the Chameleon.',
    SlotErrorCode.unsupportedCardType => cannotLoad,
    SlotErrorCode.invalidSlot => 'That slot does not exist.',
    SlotErrorCode.cancelled => uploadCancelled,
    SlotErrorCode.unknown => 'Could not load the card.',
  };

  static String dumpBlocks(int have, int total) => '$have/$total blocks';
  static String dumpSectors(int known, int total) =>
      '$known/$total sectors keys known';
  static String dumpPages(int pages) => '$pages pages';
  static const noDump = 'ID only';
}
