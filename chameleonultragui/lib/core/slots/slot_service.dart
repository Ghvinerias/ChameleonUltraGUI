// FROZEN CONTRACT (Track 0B). Changes require a PR labelled `contract-change`.
//
// Headless slot management: writing saved cards into emulator slots and the
// basic slot queries/updates a small (watch) UI needs.
//
// Implemented by Track T1.
//  * [SlotService.uploadCard] is extracted from `onTap` in
//    lib/gui/page/slot_manager.dart (the per-card-type branches: Mifare
//    Classic, Ultralight/NTAG, `hf14a4` via `writeHf14a4SlotIdentity`,
//    EM410X, HID, Viking, PAC, IoProx, Idteck).
//  * Queries are extracted from `loadSlotData` (same file) and
//    `ChameleonCommunicator.getSlotTagTypes/getEnabledSlots/getSlotTagNames`.
//  * enable / activate / rename wrap `enableSlot`, `activateSlot`,
//    `setSlotTagName` + `saveSlotData`.
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';

/// Error categories for slot operations (not localized text).
enum SlotErrorCode {
  notConnected,
  communication,

  /// Card type cannot be written to a slot yet (`Can't write this card type
  /// yet.` today).
  unsupportedCardType,

  /// Slot index outside 0..7.
  invalidSlot,

  /// Upload was cancelled via [SlotUpload.cancel].
  cancelled,
  unknown,
}

/// Progress/terminal events of an upload. Sealed.
sealed class SlotUploadEvent {
  const SlotUploadEvent();
}

/// Slot prepared (reader mode off, slot enabled/activated, type set, default
/// data set, anti-collision written) and data transfer begins.
final class SlotUploadStarted extends SlotUploadEvent {
  final int slot;

  const SlotUploadStarted(this.slot);
}

/// 0..100, same scale the phone progress bar uses (blocks or pages written).
/// Not emitted for LF cards (instant).
final class SlotUploadProgress extends SlotUploadEvent {
  final int percent;

  const SlotUploadProgress(this.percent);
}

/// Terminal success: name set and `saveSlotData` done.
final class SlotUploadDone extends SlotUploadEvent {
  final int slot;

  const SlotUploadDone(this.slot);
}

/// Terminal failure.
final class SlotUploadFailed extends SlotUploadEvent {
  final SlotErrorCode code;
  final String? detail;

  const SlotUploadFailed(this.code, {this.detail});
}

/// A running upload.
abstract class SlotUpload {
  /// Broadcast stream; ends with exactly one of [SlotUploadDone] /
  /// [SlotUploadFailed] (cancellation = `SlotUploadFailed(cancelled)`), then
  /// closes. Events before listening are not replayed.
  Stream<SlotUploadEvent> get events;

  /// Completes with the terminal event; never throws.
  Future<SlotUploadEvent> get terminal;

  /// Stops after the in-flight command. The slot may be left partially
  /// written, exactly as when the phone upload is interrupted.
  Future<void> cancel();
}

/// One slot as the UI shows it.
class SlotInfo {
  /// 0..7.
  final int index;
  final TagType hfType;
  final TagType lfType;
  final bool hfEnabled;
  final bool lfEnabled;

  /// Empty string when unnamed. The UI substitutes its own localized
  /// "no name" text.
  final String hfName;
  final String lfName;

  const SlotInfo({
    required this.index,
    this.hfType = TagType.unknown,
    this.lfType = TagType.unknown,
    this.hfEnabled = false,
    this.lfEnabled = false,
    this.hfName = '',
    this.lfName = '',
  });
}

abstract class SlotService {
  /// Number of emulator slots (8 on Chameleon Ultra/Lite).
  static const int slotCount = 8;

  /// Whether [card] has an upload path (MFC, MFU/NTAG, hf14a4, EM410X, HID,
  /// Viking, PAC, IoProx, Idteck).
  bool canUpload(CardSave card);

  /// Writes [card] into [slot] (0..7). Must NOT mutate [card] (the phone code
  /// currently rewrites `card.tag` to `mifare2K` for EV1 dumps; the service
  /// works on a copy). [emptyNameFallback] replaces an empty `card.name` (the
  /// phone passes its localized "no name"), since the service has no
  /// localizations.
  SlotUpload uploadCard(
    CardSave card,
    int slot, {
    String emptyNameFallback = '',
  });

  /// Reads all 8 slots (types, enabled flags, names) in one call.
  Future<List<SlotInfo>> getSlots();

  /// Currently active slot index.
  Future<int> getActiveSlot();

  /// Makes [slot] the active emulation slot.
  Future<void> activateSlot(int slot);

  /// Enables/disables the HF or LF half of [slot] (`enableSlot`) and persists.
  Future<void> setSlotEnabled(int slot, TagFrequency frequency, bool enabled);

  /// Renames the HF or LF half of [slot] (`setSlotTagName`) and persists
  /// (`saveSlotData`).
  Future<void> renameSlot(int slot, TagFrequency frequency, String name);
}
