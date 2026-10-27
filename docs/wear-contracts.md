# Wear OS port: frozen contracts

Produced by Track 0B. Source plan: `docs/WEAR_OS_PORT_PLAN.md` (sections 2, 4, 8).
All paths are relative to `chameleonultragui/`.

## Freeze rule

The files listed below are **frozen** as of the end of Track 0B. Changing a
signature, enum value, wire field or documented behaviour needs a PR labelled
`contract-change`. Such PRs merge first; every affected track rebases onto
them. Additive, backward-compatible changes (new optional field, new enum
value that old code can ignore) still need the label so owners are notified.
`WatchInstaller` (Track 0D) and the plugin method channels (T5, 0D) are frozen
by their own tracks under the same rule.

## Contracts

| File | Purpose | Implemented by |
|---|---|---|
| `lib/models/dictionary.dart` | `Dictionary`, `DictionaryFolder`, `DictionaryFolderBundle` (moved verbatim) plus optional `updatedAt` | already implemented (0B); merge helpers T4 |
| `lib/models/card_save.dart` | `CardSave`, `CardSaveExtra` (moved) plus optional `updatedAt` | same |
| `lib/models/card_folder.dart` | `CardFolder`, `CardFolderBundle` (moved) plus optional `updatedAt` | same |
| `lib/models/sync_tombstone.dart` | `SyncTombstone`, `SyncEntityKind` (card, cardFolder, dictionary, dictionaryFolder) | implemented (0B) |
| `lib/sharedprefsprovider.dart` | still re-exports all models so no other import changes | 0B, then T7 |
| `lib/core/read/read_service.dart` | `ReadService`, `ReadSession`, sealed `ReadEvent` (scanning, card detected, checking keys, recovery progress, dump progress, done, failed, cancelled), `ReadErrorCode`, `HfReadOptions` (dictionaries to use), `ContinuousScanOptions`, result and state classes. Context-free, no localized strings | **T1** (extract from `readHFInfo`, `performMifareClassicScan`, `MifareClassicRecovery`, `readLFInfo`, continuous scan timers) |
| `lib/core/slots/slot_service.dart` | `SlotService` (`uploadCard` with progress/cancel, `getSlots`, `activateSlot`, `setSlotEnabled`, `renameSlot`), `SlotUploadEvent`, `SlotErrorCode`, `SlotInfo` | **T1** (extract from `slot_manager.dart` `onTap` and `loadSlotData`) |
| `lib/core/stores/card_store.dart` | `CardStore`: CRUD + folders. Every create/update stamps `updatedAt`; every delete records a `SyncTombstone`; `*FromSync` methods apply remote state verbatim; `changes` stream | **T7** |
| `lib/core/stores/dictionary_store.dart` | `DictionaryStore`: same rules | **T7** |
| `lib/core/stores/store_change.dart` | `StoreChange`, `StoreChangeType`, `StoreChangeOrigin` | T7 (emits), T4 (consumes) |
| `lib/sync/sync_models.dart` | `kSyncProtocolVersion`, `SyncHandshake`, `SyncManifest(Entry)` `(kind,id,updatedAt,hash,size)`, `SyncMessage` envelope, `BulkHeader`, `SyncRole` | **T4** (uses), data classes implemented (0B) |
| `lib/sync/sync_transport.dart` | `SyncTransport`: peer availability, small messages, chunk-level bulk transfer (`BulkSender`/`IncomingBulk`) with byte progress and cancel | **T5** (Wear Data Layer impl via `wear_sync`); **T4** consumes; fake in `test/fakes` |

## Key semantics other tracks must know

- **Sessions, not futures.** `ReadService` and `SlotService.uploadCard` return a
  session object exposing a broadcast `events` stream, a `terminal` future and
  `cancel()`. Exactly one terminal event is emitted. Events are not replayed to
  late listeners; attach immediately. One read session at a time per device.
- **No localization in core.** Errors are enums; phase and counters are data.
  `SlotService.uploadCard` takes `emptyNameFallback` instead of localizations.
- **`uploadCard` must not mutate the `CardSave`** (the phone code today rewrites
  `tag` to `mifare2K` for EV1 dumps; the service works on a copy).
- **Updated-at stamping lives in the stores**, never in UI code. `updatedAt`
  is epoch milliseconds, `null` on legacy data, serialised only when set. The
  manifest reports a missing stamp as `0`.
- **Tombstone rule (T4):** a tombstone wins if `deletedAt > updatedAt`; ties go
  to the phone.
- **Transport reliability model:** messages and bulk chunks may be lost,
  duplicated or reordered. The transport only moves bytes; T4 owns reassembly,
  SHA-256 verification, resume-by-chunk-index and the protocol handshake. Large
  data (more than `maxMessageBytes`, about 100 KB) must use bulk.
- `read_service.dart` currently imports `MifareClassicType` from
  `helpers/mifare_classic/general.dart`. If T1 moves that enum, T1 updates the
  import; the type name stays.

## Additive changes made by Track T1a (read service)

All backward compatible; `lib/core/read/read_service.dart`:

- `ReadErrorCode.hardnestedUnavailable`: the card needs the hardnested attack
  but `HfReadOptions.allowHardnested` is false. Terminal `ReadFailed`.
- `HfReadOptions.allowHardnested` (default `true`; the watch passes `false`).
- `ReadRecoveryProgress.viaBackdoor` (default `false`): the nested attack
  seeded through the card's backdoor key.
- Conventions (no signature change): an old firmware that returns no hardnested
  nonces ends with `ReadFailed(recoveryFailed, detail: 'firmware_too_old')`;
  `ReadDumpProgress.blocksDone` is the index of the block just read (the phone's
  progress bar value), so the last event is `blocksTotal - 1`.
- `continueMifareClassic` is cumulative: from `identify` with depth
  `recoverKeys` it runs the key check first; recovery is skipped when all keys
  are already found.

Implementation: `ReadServiceImpl` (`lib/core/read/read_service_impl.dart`),
headless engine `MifareClassicEngine`, injectable `KeyRecoveryBackend`
(`NativeKeyRecoveryBackend` is the default, tests use
`test/core/read/fake_key_recovery_backend.dart`).

## Test doubles (`test/fakes/`)

- `FakeChameleonCommunicator` (+ `FakeCard`): subclass of
  `ChameleonCommunicator` built with no serial port. It overrides the
  read/slot methods at method level; every non-overridden command reaches an
  overridden `sendCmd` that throws `UnimplementedError` naming the command.
  Scripted cards: `none`, `mfc1kDefaultKeys` (optionally EV1),
  `mfc1kCustomKey`, `ntag215`, `em410x`. `scanScript` makes successive scan
  attempts see successive cards (for continuous-scan tests); `callLog`,
  `slots`, `failNext` and `beforeCommand` support assertions, error injection
  and cancellation interleaving.
- `InMemorySyncTransport.pair()`: connected phone/watch pair with `chunkHook`
  (drop / duplicate / hold-and-`flushHeld()` to reorder), `messageHook`,
  `setPeerAvailable`, cancel from either side and link-loss aborts.

Both are exercised by `test/fakes/*_test.dart`.

## Sync engine (Track T4)

Implementation: `lib/sync/sync_engine.dart` (`SyncEngine`, `SyncSession`),
`sync_run.dart` (protocol), `sync_records.dart` (records, snapshot,
`computeSyncPlan`), `sync_normalize.dart` (orphan repair), `sync_blob.dart`
(chunking/resume), `sync_report.dart`, `sync_errors.dart`, `sync_types.dart`.
Model helpers: `lib/models/sync_extensions.dart`. Test doubles:
`test/fakes/in_memory_{card,dictionary}_store.dart`.

### Sync merge rules

- Per entity id (kinds: card, cardFolder, dictionary, dictionaryFolder) each
  replica has one *record*: live (`updatedAt`, missing = 0) or dead
  (`deletedAt`). An entity and a tombstone of the same id on one replica resolve
  with "tombstone wins iff `deletedAt > updatedAt`".
- live vs live: newer `updatedAt` wins; equal stamps with different content go
  to the phone (counted in `SyncReport.conflictsResolved`).
- live vs dead: dead wins iff `deletedAt > updatedAt`; on equal stamps the phone's
  side wins (phone live: restored, phone dead: deleted).
- A tombstone is only propagated to a replica that still holds the entity;
  dead/dead and dead/absent change nothing (so tombstone sets may differ).
- **Mirror mode** (`SyncOptions.mirrorDictionaries`, phone's value is sent in
  the handshake; covers dictionaries and dictionary folders only): the watch
  gets exactly the phone's state; watch-only or watch-edited dictionaries are
  overwritten/removed; nothing flows watch -> phone for them.
- **Orphan rule:** after the merge, an item or folder whose folder/parent is not
  live moves to the root (field removed, `updatedAt` untouched, counted in
  `orphansMovedToRoot`). A parent cycle (possible when two replicas move folders
  into each other) is broken by moving the cycle member with the smallest id to
  the root. Both replicas compute this on the same final content, so no extra
  data is exchanged.
- Apply order: item deletes, folder puts (parents first), item puts, folder
  deletes (children first). Clocks are not reconciled (skew between phone and
  watch affects which writer is "last").

### Protocol

`sync.hello`/`hello-ack` (version check, `kSyncMinProtocolVersion` ..
`kSyncProtocolVersion`) -> manifest blobs both ways -> both sides compute the
same plan -> bundle blobs (`CardFolderBundle` / `DictionaryFolderBundle` with
`rootFolderId: ''`, i.e. "whole library") -> stage + SHA-256 verify + compare
each item's hash with the manifest -> `sync.ready` (watch) -> `sync.commit`
(phone) -> watch commits, `sync.done` -> phone commits. Blobs are
content-addressed (`purpose:sha256`), offered by message, pulled by chunk-index
ranges (`sync.want`), acknowledged with `sync.ack`; everything is retried every
`retryInterval`. Unfinished blobs stay in the receiver's `SyncResumeCache`, so a
retry after link loss only fetches the missing chunks. Nothing touches a store
before commit; if a replica changed during the sync, it fails with `dataChanged`
(safe to retry). If a commit throws, the engine rolls back best effort and
reports `storeFailure`. Cross-device atomicity is "watch first, phone second":
if the link dies between the two commits the watch has applied and the phone
has not, and the next sync converges.

### Requirements on the real stores (T7)

- `putCardFromSync` / `putDictionaryFromSync` / `put*FolderFromSync` MUST also
  remove a tombstone of the same id (rollback and resurrection rely on it).
- `deleteFromSync` MUST remove only the one entity (no folder cascade) and
  record exactly the tombstone it is given; it must tolerate a missing entity.
- Reading must round-trip: `toJson()` of a stored-and-reloaded entity must be
  byte-identical (the manifest hash is SHA-256 of `toJson()`).

### Additive changes to frozen files

None.
