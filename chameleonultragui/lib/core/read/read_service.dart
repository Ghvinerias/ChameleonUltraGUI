// FROZEN CONTRACT (Track 0B). Changes require a PR labelled `contract-change`.
//
// Headless HF/LF card reading. No BuildContext, no Provider, no localized
// strings: everything the UI needs is a typed event or a result object, and
// the UI decides how to render it.
//
// Implemented by Track T1 by extracting existing logic:
//  * [ReadService.readHf]  <- `readHFInfo` (lib/helpers/general.dart), which
//    calls `performMifareClassicScan` (lib/helpers/mifare_classic/general.dart)
//    and `performMifareUltralightScan`.
//  * MFC key check / recovery / dump <- `MifareClassicRecovery.checkKeys`,
//    `.recoverKeys`, `.dumpData` (lib/helpers/mifare_classic/recovery.dart).
//    Those currently write localized text into `MifareClassicRecovery.state`
//    and `.error`; they must instead emit [ReadPhase] / [ReadErrorCode].
//  * [ReadService.readLf] <- `ReadCardPageState.readLFInfo`
//    (lib/gui/page/read_card.dart): EM410X, HID, Viking, PAC, IoProx probed in
//    that order.
//  * continuous scans <- `startContinuousHFScan` / `startContinuousLFScan` in
//    the same page (2 s interval, 1 min cap, stop at first card found).
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart'
    show MifareClassicType;
import 'package:chameleonultragui/models/dictionary.dart';

/// Which radio a read targets.
enum ReadFrequency { hf, lf }

/// How far an HF read of a Mifare Classic card should go. Cumulative: each
/// level includes the previous ones. Non-MFC cards ignore this.
enum MifareClassicDepth {
  /// Detect type, EV1, NT level, backdoor. No key checking (what
  /// `readHFInfo` does today).
  identify,

  /// `identify` + check all sectors against the dictionaries and defaults.
  checkKeys,

  /// `checkKeys` + darkside / nested / static-nested / hardnested / backdoor
  /// recovery for the missing keys.
  recoverKeys,

  /// `recoverKeys` + dump every readable block.
  dump,
}

/// Error categories. Deliberately NOT localized text: the UI maps each code to
/// its own string. [ReadFailed.detail] carries optional developer text only.
enum ReadErrorCode {
  /// No communicator / device connection.
  notConnected,

  /// Serial / BLE command failed or timed out.
  communication,

  /// The card left the field mid-operation.
  cardLost,

  /// Card is not supported by this flow.
  unsupportedCard,

  /// Reserved: key recovery found no usable key to start from
  /// (`recovery_error_no_keys_darkside` today).
  noKeysForRecovery,

  /// An attack ran and failed.
  recoveryFailed,

  /// The native recovery library is unavailable (e.g. `librecovery.so` did
  /// not load).
  recoveryUnavailable,

  /// Dumping blocks failed.
  dumpFailed,

  /// Operation exceeded its time budget.
  timeout,

  /// Anything else; see [ReadFailed.detail].
  unknown,
}

/// Coarse phase of a read, for progress UIs.
enum ReadPhase {
  /// Waiting for / probing the field for a card.
  scanning,

  /// Identifying card type (MFC vs MFU vs other).
  identifying,

  /// Checking dictionary / default keys.
  checkingKeys,

  /// Running a key recovery attack.
  recovering,

  /// Reading blocks into a dump.
  dumping,
}

/// Key recovery attack in progress (see `MifareClassicRecovery.recoverKeys`).
enum RecoveryAttack {
  /// Probing which attack applies (PRNG level, backdoor presence).
  detecting,
  darkside,
  nested,
  staticNested,
  hardnested,

  /// Known-backdoor (FM11RF08S etc.) recovery.
  backdoor,
}

/// Per-sector key state. Maps 1:1 to the phone's `ChameleonKeyCheckmark`.
enum SectorKeyState { none, found, checking, disabled }

/// Base of everything a read emits. Sealed so UIs can switch exhaustively.
sealed class ReadEvent {
  const ReadEvent();
}

/// Field is on, polling for a card.
final class ReadScanning extends ReadEvent {
  final ReadFrequency frequency;

  /// 1-based attempt counter for continuous scans; 1 for single reads.
  final int attempt;

  const ReadScanning(this.frequency, {this.attempt = 1});
}

/// A card answered. Emitted once the UID/ATQA/SAK (HF) or ID (LF) is known,
/// before any deeper work.
final class ReadCardDetected extends ReadEvent {
  final ReadFrequency frequency;

  /// HF only (null for LF).
  final CardData? hfCard;

  /// LF only (null for HF).
  final LFCard? lfCard;

  const ReadCardDetected(this.frequency, {this.hfCard, this.lfCard});
}

/// Key checking progress.
final class ReadCheckingKeys extends ReadEvent {
  /// Sector currently being checked (0-based).
  final int sector;

  /// 0 = key A, 1 = key B.
  final int keyType;

  /// Number of candidate keys for this sector (dictionary + defaults).
  final int keyCount;

  /// Chunks of keys already sent / total chunks for this sector. Today the
  /// phone only shows a bar when total > 10.
  final int chunksDone;
  final int chunksTotal;

  /// Sectors fully resolved so far / total sectors on the card.
  final int sectorsDone;
  final int sectorsTotal;

  /// Snapshot of per-sector state (index = sector * 2 + keyType, length 80).
  final List<SectorKeyState> sectorStates;

  const ReadCheckingKeys({
    required this.sector,
    required this.keyType,
    required this.keyCount,
    required this.chunksDone,
    required this.chunksTotal,
    required this.sectorsDone,
    required this.sectorsTotal,
    required this.sectorStates,
  });
}

/// Darkside / nested / hardnested ... progress.
final class ReadRecoveryProgress extends ReadEvent {
  final RecoveryAttack attack;

  /// Sector/key type being attacked; null while [attack] is `detecting`.
  final int? sector;
  final int? keyType;

  /// Sub-step of the attack, informational.
  final RecoveryStep step;

  /// 0..1 when the step has measurable progress (hardnested nonce
  /// collection), otherwise null (indeterminate).
  final double? progress;

  /// Keys recovered so far in this read.
  final int keysFound;

  const ReadRecoveryProgress({
    required this.attack,
    required this.step,
    this.sector,
    this.keyType,
    this.progress,
    this.keysFound = 0,
  });
}

/// What the attack is doing right now.
enum RecoveryStep { collectingNonces, recoveringKey, verifyingKey }

/// Dump progress in blocks.
final class ReadDumpProgress extends ReadEvent {
  final int blocksDone;
  final int blocksTotal;

  const ReadDumpProgress(this.blocksDone, this.blocksTotal);

  double get fraction => blocksTotal == 0 ? 0 : blocksDone / blocksTotal;
}

/// Terminal success. Always the last event before the stream closes.
final class ReadDone extends ReadEvent {
  final ReadResult result;

  const ReadDone(this.result);
}

/// Terminal failure.
final class ReadFailed extends ReadEvent {
  final ReadErrorCode code;

  /// Developer-facing text only (log, never shown verbatim to the user).
  final String? detail;

  const ReadFailed(this.code, {this.detail});
}

/// Terminal: the session was cancelled via [ReadSession.cancel] (or a
/// continuous scan hit its time cap / was stopped).
final class ReadCancelled extends ReadEvent {
  /// True when a continuous scan ended because `maxDuration` elapsed.
  final bool timedOut;

  const ReadCancelled({this.timedOut = false});
}

/// Result payload of [ReadDone].
sealed class ReadResult {
  const ReadResult();
}

/// HF read outcome. [card] null means "no card present" (not an error).
final class HfReadResult extends ReadResult {
  final CardData? card;

  /// Chameleon tag type; `TagType.unknown` when no card.
  final TagType type;

  /// Present when the card is Mifare Classic.
  final MifareClassicReadState? mifareClassic;

  /// Present when the card is Mifare Ultralight / NTAG.
  final MifareUltralightReadState? mifareUltralight;

  const HfReadResult({
    this.card,
    this.type = TagType.unknown,
    this.mifareClassic,
    this.mifareUltralight,
  });

  bool get cardPresent => card != null;
}

/// LF read outcome. [card] null means no card present.
final class LfReadResult extends ReadResult {
  final LFCard? card;

  const LfReadResult({this.card});

  bool get cardPresent => card != null;
}

/// Everything known about a Mifare Classic card. Also the input to
/// [ReadService.continueMifareClassic] so a UI can step identify -> keys ->
/// recovery -> dump on user action, as the phone page does today.
class MifareClassicReadState {
  final MifareClassicType type;
  final bool isEV1;
  final NTLevel? ntLevel;
  final bool? hasBackdoor;

  /// Length 80 (40 sectors x A/B). Index = sector * 2 + keyType.
  final List<SectorKeyState> sectorStates;

  /// Length 80. Empty `Uint8List` where unknown.
  final List<Uint8List> keys;

  /// Length 256 blocks. Empty `Uint8List` for blocks not read.
  final List<Uint8List> blocks;

  /// True once every sector of the card has both keys found or disabled.
  final bool allKeysFound;

  /// Depth already completed.
  final MifareClassicDepth completedDepth;

  const MifareClassicReadState({
    required this.type,
    required this.isEV1,
    required this.sectorStates,
    required this.keys,
    required this.blocks,
    this.ntLevel,
    this.hasBackdoor,
    this.allKeysFound = false,
    this.completedDepth = MifareClassicDepth.identify,
  });
}

/// Mifare Ultralight / NTAG info (see `performMifareUltralightScan`).
class MifareUltralightReadState {
  final Uint8List? version;
  final Uint8List? signature;

  /// Dumped pages (4 bytes each), empty when not dumped.
  final List<Uint8List> pages;

  const MifareUltralightReadState({
    this.version,
    this.signature,
    this.pages = const [],
  });
}

/// Inputs of an HF read.
class HfReadOptions {
  /// How far to go for Mifare Classic cards.
  final MifareClassicDepth depth;

  /// User dictionaries to try first, in order. The service always appends the
  /// built-in default keys (`gMifareClassicKeys`) unless
  /// [skipDefaultDictionary] is true, matching `checkKeys`.
  final List<Dictionary> dictionaries;

  /// Dictionary (by `Dictionary.id`) used as the primary list; defaults to the
  /// first entry of [dictionaries] when null.
  final String? primaryDictionaryId;

  /// Mirrors `MifareClassicRecovery.checkKeys(skipDefaultDictionary:)`.
  final bool skipDefaultDictionary;

  const HfReadOptions({
    this.depth = MifareClassicDepth.identify,
    this.dictionaries = const [],
    this.primaryDictionaryId,
    this.skipDefaultDictionary = false,
  });
}

/// Inputs of a continuous scan.
class ContinuousScanOptions {
  /// Pause between probes (phone: 2 s).
  final Duration interval;

  /// Hard cap (phone: 1 min). On expiry the session ends with
  /// `ReadCancelled(timedOut: true)`.
  final Duration maxDuration;

  /// Finish with [ReadDone] at the first card found (phone behaviour). When
  /// false, every detection is emitted as [ReadDone]-less
  /// [ReadCardDetected] and the scan keeps going until stopped/capped.
  final bool stopOnFound;

  /// Applies to HF scans only; defaults to [MifareClassicDepth.identify].
  final HfReadOptions hf;

  const ContinuousScanOptions({
    this.interval = const Duration(seconds: 2),
    this.maxDuration = const Duration(minutes: 1),
    this.stopOnFound = true,
    this.hf = const HfReadOptions(),
  });
}

/// One running read or scan. Cancellable, observable, single-use.
abstract class ReadSession {
  /// Broadcast stream of progress. Always ends with exactly one terminal event
  /// ([ReadDone], [ReadFailed] or [ReadCancelled]) and then closes. Events
  /// emitted before a listener attaches are NOT replayed; listen immediately.
  Stream<ReadEvent> get events;

  /// Completes with the terminal event. Never throws.
  Future<ReadEvent> get terminal;

  /// Requests cancellation. Idempotent. The session stops issuing commands as
  /// soon as the in-flight one returns and emits [ReadCancelled]. For a
  /// continuous scan this is the "stop" operation.
  Future<void> cancel();

  /// True once the terminal event has been emitted.
  bool get isFinished;
}

/// Headless read pipeline. One instance per connected device; at most one
/// session runs at a time (the device is a single serial channel): starting a
/// second while one is active throws [StateError].
abstract class ReadService {
  /// Single HF read. Extracted from `readHFInfo` (+ `MifareClassicRecovery`
  /// for depths beyond `identify`).
  ReadSession readHf({HfReadOptions options = const HfReadOptions()});

  /// Continues a Mifare Classic read from a prior [MifareClassicReadState]
  /// (for example run `recoverKeys` after the user inspected key-check
  /// results). Extracted from the phone's step buttons
  /// (`checkKeys` / `recoverKeys` / `dumpData`).
  ReadSession continueMifareClassic(
    MifareClassicReadState from, {
    required MifareClassicDepth depth,
    HfReadOptions options = const HfReadOptions(),
  });

  /// Single LF read (extracted from `readLFInfo`).
  ReadSession readLf();

  /// Continuous HF scan. Extracted from `startContinuousHFScan`. Stop with
  /// [ReadSession.cancel].
  ReadSession startContinuousHfScan({
    ContinuousScanOptions options = const ContinuousScanOptions(),
  });

  /// Continuous LF scan. Extracted from `startContinuousLFScan`.
  ReadSession startContinuousLfScan({
    ContinuousScanOptions options = const ContinuousScanOptions(),
  });
}
