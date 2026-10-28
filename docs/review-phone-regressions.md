# Review: phone regressions from the Wear OS refactor (branch feat/wear-os @ 763bc3d)

Reviewed by diffing `main...HEAD` and tracing old vs new paths. Production code was not changed.
Only the tests in `chameleonultragui/test/review/` were added.

## Summary

| ID | Severity | Area | Summary |
|----|----------|------|---------|
| P1 | medium | T7 stores | `updatedAt` stamp is raw wall clock: same-ms edits tie, and a clock that moved backwards lowers the stamp (test fails) |
| P2 | medium | T7 stores | Tombstone `deletedAt` can be older than the deleted entity's `updatedAt` under clock skew (test fails) |
| P3 | medium | T7 stores | `setCards`/`setDictionaries`/folders now read and decode storage first; one unreadable entry makes every save throw. The old setters just overwrote (2 tests fail) |
| P4 | medium | T1b slots | A failed slot upload no longer throws: it is logged, then `changesMade()` and `refreshSlot()` run. Old code threw and left the progress bar where it was |
| P5 | low | T1a read | Errors outside the old `try` (reader mode, `scan14443aTag`, any LF probe) now surface as `ReadFailedException` instead of the original exception |
| P6 | low | T1a read | `phoneReadService()` dereferences `appState.connector!` for every read, including LF and HF identify, which never needed it |
| P7 | low | T1a read | Darkside retry resets `state` to the darkside text each try. Old code left "checking keys (n)" after a failed key check |
| P8 | low | T1b slots | HF14a4 progress reaches 100 before name/save instead of after |
| P9 | low | T1b slots | EV1 `card.tag = mifare2K` rewrite now hits a copy; the caller's `CardSave` is no longer mutated |
| P10 | low | T7 stores | Exported/serialised cards, dictionaries and folders now carry `updatedAt` |
| P11 | low | T7 stores | `replaceAll` JSON-encodes and compares every stored and incoming item on each save (performance, unmeasured) |
| P12 | low | T7 stores | `setX` now mutates the caller's objects (`updatedAt`). Legacy items stay `updatedAt == null` until edited |

No high-severity (wrong result or data loss) discrepancy was found in the read flow.

## Details

### P1 stamps: same millisecond and clock going backwards
- New: `lib/core/stores/prefs_collection.dart:131-150` (`replaceAll` stamps with `now = clock()`), and `save()` at about line 108. Old: no stamps.
- Scenario A: two edits of card `a` within one millisecond get an identical `updatedAt`. Last-writer-wins sync cannot order them.
- Scenario B: the clock is set from 5000 back to 1000. The next edit stamps 1000, lower than the 5000 it replaces, so a peer keeps the older version.
- Fix: stamp `max(clock(), previousUpdatedAt + 1)` per item.
- Tests: `test/review/prefs_stamp_regressions_test.dart` (both "P1" tests fail).

### P2 tombstone older than the entity
- New: `prefs_collection.dart:152-156` records `deletedAt: now`.
- Scenario: card `a` has `updatedAt` 5000; the clock reads 1000 when it is deleted. A peer holding `updatedAt` 5000 sees the entity as newer than the tombstone and resurrects it.
- Fix: `deletedAt = max(now, old.updatedAt + 1)`.
- Test: the "P2" test fails.
- Related and unverified: `pruneExpired()` in `load()` uses the same wall clock. A clock set far into the future prunes all tombstones.

### P3 setters now depend on readable storage
- Old: `sharedprefsprovider.dart` `setCards`/`setDictionaries`/`setCardFolders`/`setDictionaryFolders` only wrote.
- New: `PrefsCollection.replaceAll` starts with `list()`, which runs `fromJson` on every stored entry.
- Scenario: `cards` holds one malformed or unknown-tag entry. Old `setCards([...])` replaced it. New throws `FormatException`, so a UI path that tried to repair or clear the list can no longer do so.
- Fix: decode stored entries leniently in `replaceAll`, treating undecodable ones as absent.
- Tests: both "P3" tests fail.

### P4 upload failure handling
- Old: `slot_manager.dart` `onTap` (main) let any exception propagate. `refreshSlot()` ran only on success, so the progress bar stayed at its partial value.
- New: `slot_manager.dart:102-115`. Failures become `SlotUploadFailed`, are logged, and `changesMade()` and `refreshSlot()` (which sets progress to -1) always run. The user sees no error either way.
- Net effect: the bar now clears after a failure and the exception is swallowed. This is arguably better, but it is a change. No test (needs a widget harness).

### P5 exception type
- Old: `scan14443aTag`, `isReaderDeviceMode` and LF reads sat outside the `try`, so the raw exception propagated. Failures inside the `try` were swallowed into `cardExist = false`; the new code keeps that via `cardLost`.
- New: `helpers/general.dart:678-681` and `read_card.dart:126-128` throw `ReadFailedException`. The callers (timer callbacks, `write/base.dart:177`) have no `catch`, so the result is unhandled either way and only the type differs.

### P6 connector dereference
- New: `helpers/general.dart` `phoneReadService` evaluates `appState.connector!.connectionType` eagerly. Old `readHFInfo` and LF did not use the connector.
- Unverified: `connector` is set to null in `settings.dart:621` and `debug.dart:77/90`, but I did not confirm `communicator` can stay non-null in those cases.

### P7 darkside state text
- Old `recoverKeys`: `state` was set to the darkside text once. A failed `checkKeysOnSector` then left "checking keys (n)" visible during the next `getMf1Darkside`.
- New: `mifare_classic_engine.dart` emits `darkside/recoveringKey` every try, and the adapter resets the text. Cosmetic.

### P8 HF14a4 progress ordering
- Old: `setUploadState(100)` came after `saveSlotData`.
- New: `slot_service_impl.dart` emits 100 before `setSlotTagName`/`saveSlotData`. MFC and MFU already behaved this way in the old code.

### P9 EV1 tag mutation
- Old: `card.tag = TagType.mifare2K` modified the caller's object.
- New: `_copy` isolates it. This is harmless unless the same instance was later saved.

### P10-P12
- P10: `CardSave`/`Dictionary`/folder `toJson` add `updatedAt` when non-null. This appears in exported files and bundles.
- P11: `_withoutStamp` runs `jsonDecode(toJson)` for each item on every `setCards`. Large 4K dumps make saves heavier. I did not measure it.
- P12: `replaceAll` writes `updatedAt` back onto the objects it was given. Unchanged legacy items keep a null stamp, which is correct but means the sync layer must treat null as 0 (unverified).

## Verified equivalent
- **Classic identify**: command order is unchanged (type, EV1 auth, NT level with `catch`, backdoor). `override` is handled the same way.
- **HF read**: reader mode, scan, `detectMf1Support`, then classic or ultralight. MFU version/signature are set only when the version is 8 bytes. `uid`/`sak`/`atqa`/`ats`/`tech` ("EV1" suffix) and `mfcInfo.state` are identical. A card lost mid-read gives `cardExist = false`.
- **LF read**: probe order EM410X, HID, Viking, PAC, IoProx, with the same reader-mode handling.
- **Key check**:
  - Chunk size is 32 on BLE and 64 on USB.
  - The progress bar appears only above 10 chunks, as `i/total`.
  - `checking_keys(n)` is shown, and `checking_keys(1)` during `recheckKey`.
  - Already-found and disabled sectors are skipped.
  - EV1 keys are preset.
  - `allKeysExists` is computed the same way.
- **Recovery**:
  - Command order: backdoor probe, static-encrypted acquire, `isStaticEncrypted`, NT level.
  - Darkside runs only if no key is known, the card is not static-encrypted and the NT level is not static. It makes 5 tries with a re-fetch when no key results.
  - Backdoor nested: 3 loops.
  - The attack is selected by NT level, and tries are 1 for backdoor and static, 5 otherwise.
  - Hardnested runs on a 256-nonce loop, validates the sum list and restarts on a bad sum.
  - Hardnested progress is reset when recovery starts.
  - Strings and errors: `no_keys_darkside` (and `state = ""`), `recovery_old_firmware` (without clearing `state`), `collecting_nonces`, `recovering_key`, `hardnested_collecting_nonces` and `has_backdoor_support` map one-to-one.
- **Dump**: block order and key fallback are identical, and sector-trailer keys are patched in. `dumpProgress` is `block/total`. `cardData` is copied back in a `finally`.
- **Slot upload**: command order and block chunking (128-byte boundary, `asyncSleep(1)`) match the old inline code for MFC, MFU, HF14a4 and all LF types (including em410X vs Electra). Name fallback, counters, version/signature and `mf0ResetAuthCount` are the same. The dialog is closed first, the progress bar starts at 0 only for HF, and unsupported types log and return.
- **Slot list**: same three read commands in the same order, and the empty-name fallback is applied to the wrapped copies.
- **Prefs**:
  - Order is preserved.
  - Folder changes count as updates.
  - Re-saving unchanged items keeps their stamp.
  - Removals are tombstoned, and re-adding clears the tombstone.
  - The system dictionary (id "") is skipped.
  - Duplicate ids are kept as before.
  - The `getDictionaries(keyLength:)` filter is unchanged.
  - Legacy JSON without `updatedAt` loads.
  - Storage keys are unchanged.

## Not determined
- Whether any UI path relied on the old tolerant setters (P3) to repair broken storage.
- The effect of P1/P2 on the actual sync algorithm (T4); only the store contract was checked.
- P11 performance and P6 reachability were not measured.
- Widget-level behavior (P4) and the rest of the unit-test suite were not run beyond `test/review`.

## Tests
`chameleonultragui/test/review/prefs_stamp_regressions_test.dart`: 5 tests, all fail on the current code (P1 x2, P2, P3 x2). I ran `flutter test test/review`; all 5 failed. I did not rerun the full suite or `flutter analyze`.
