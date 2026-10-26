# Wear OS port (Galaxy Watch 8 Classic): multistage implementation plan

Status: proposal. Nothing in this plan has been built yet.
Companion to the scoping discussion: read, continuous read, key dictionaries, saved cards, slot and device settings, and phone-watch sync. Firmware flashing is out of scope.

Items marked **[verify]** are assumptions or unverified claims from research. A Stage 0 task must confirm each one before anything depends on it.

---

## 1. Decisions to confirm before Stage 0

| # | Decision | Recommendation |
|---|---|---|
| D1 | Distribution for now | Sideload only. The phone installs the watch APK (section 5). The Play Wear track is deferred. |
| D2 | Build split | Gradle flavors `phone` / `wear`, same `applicationId` (`io.chameleon.ultra`). Fallback if flavors disrupt the existing release pipeline: a separate Gradle property plus a manifest overlay. |
| D3 | Signing | Commit a dev-only keystore for debug and CI builds, so phone and watch builds always share a key. Release builds keep the real keystore secret. |
| D4 | Sync semantics | Last-writer-wins per item id, with tombstones for deletes. Dictionaries have a "mirror phone to watch" switch. |
| D5 | Hardnested on the watch | Decide after the Stage 0 timing spike. Default is gated or phone-only. |
| D6 | Watch storage | Keep SharedPreferences for the MVP. Move to file-backed stores only if the Stage 0 spike shows slow startup. |

D3 matters more than it looks. `android/app/build.gradle` currently signs release builds with the **debug** key when no `key.properties` exists. CI runners generate a fresh debug keystore, so APKs from different CI jobs have different signatures. Phone and watch must share package name and signature for the Wear Data Layer to connect them. Without a shared key, sync fails and in-place upgrade installs fail with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.

---

## 2. Target architecture

```
lib/
  main.dart                 phone entry, untouched except by Track 0A
  wear/main_wear.dart       watch entry (new)
  wear/**                   watch UI, theme, screens (new)
  core/                     headless services, no BuildContext (new)
    read/                   HF/LF read pipeline, continuous scan, MFC recovery orchestration
    slots/                  upload-card-to-slot, slot settings
    stores/                 CardStore, DictionaryStore (stamp updatedAt, write tombstones)
  models/                   CardSave, Dictionary, folders, tombstones (moved out of sharedprefsprovider.dart)
  sync/                     pure Dart: manifest, diff/merge, chunking, protocol; SyncTransport interface
  installer/                phone only: WatchInstaller interface, ADB-over-Wi-Fi impl, UI
packages/
  wear_sync/                Flutter plugin: Kotlin Wear Data Layer transport
  adb_wifi/                 Flutter plugin: Kotlin ADB client (pair/connect/install), phone only
test/
  fakes/                    FakeChameleonCommunicator, InMemorySyncTransport, FakeAdb
```

Why this shape (found in the code):
- `readHFInfo(BuildContext, …)` and `performMifareClassicScan(…, BuildContext, …)` read `ChameleonGUIState` through Provider. `MifareClassicRecovery` stores localized strings in its `state` field. The slot-upload logic lives inline in `slot_manager.dart`'s `onTap`. All of it must become context-free before a watch UI can reuse it.
- `ChameleonCommunicator` (`bridge/chameleon.dart`) and the connectors are already UI-independent. `AndroidSerial` already combines USB OTG and BLE.
- `CardFolderBundle` and `DictionaryFolderBundle` (`sharedprefsprovider.dart`) are versioned JSON, which makes them a ready wire format.
- `EmulatorSerial` only replays a canned hex map. It cannot drive real read flows, so tests need a method-level fake communicator.

Contract freeze: the interfaces in `core/`, `models/`, `sync/` and the `SyncTransport` / `WatchInstaller` / plugin method channels are fixed at the end of Track 0B. After that, changing one needs a PR labelled `contract-change` and every affected track rebases.

---

## 3. Stage graph and gates

```
STAGE 0 (parallel, ~1 week)
  0A  Build/CI/flavors/signing ───────────┐
  0B  Contracts, model move, fakes ───────┤
  0C  Hardware spike (needs 0A APK) ──────┼──► GATE G0
  0D  Phone installer (spike → plugin) ───┘     (0D continues into Wave 1)

WAVE 1 (parallel, ~2–3 weeks, after G0)
  T1  Core refactor: read + slot upload headless
  T2  Watch shell + UI kit (round layout, theme, rotary, goldens)
  T3  Watch connection layer (BLE-only, permissions, reconnect)
  T4  Sync engine (pure Dart) + data-model timestamps/tombstones
  T5  wear_sync plugin (Kotlin) + transport
  T6  Installer UI/plugin completion (continues 0D)
  T7  Stores layer (route all mutations through stores)       ──► GATE G1

WAVE 2 (parallel, ~2–3 weeks, after G1)
  F1  Read screens        F2  Saved cards      F3  Slots + slot settings
  F4  Device settings     F5  Dictionaries     F6  Sync UX (watch + phone)
                                                              ──► GATE G2

WAVE 3 (~2 weeks)
  H1 hardware matrix & fixes   H2 battery/thermal/perf   H3 release pipeline + docs
                                                              ──► GATE G3
```

| Gate | Pass criteria | If it fails |
|---|---|---|
| **G0** | BLE connect and a command round-trip works on the real watch. The watch ABI is known and the app installs. The native lib loads. Hardnested is timed. The sideload path works (any method). | BLE failure is a stop-and-redesign (for example phone relay). Other failures re-scope individual tracks. |
| **G1** | Contracts frozen. The phone app passes all tests unchanged after the T1 and T7 refactors. Two paired devices (real or emulator) sync a test bundle. The in-app installer installs on the real watch. | Block Wave 2 until fixed. |
| **G2** | All six feature areas work against the fake communicator and emulator. One real-hardware pass finds no blocker. | Feed bugs back to the owning track. |
| **G3** | The hardware matrix (section 6) is green. A signed release APK is published. The docs are done. | Fix, then re-run the matrix. |

---

## 4. Track details

Size key: S ≈ 2–3 days, M ≈ 1 week, L ≈ 2 weeks of a focused agent plus review. "Owns" lists the files a track may edit. Everything else is read-only for that track, so tracks do not conflict.

### Stage 0

**0A: Build, CI, flavors, signing** (M)
- Owns: `android/**`, `.github/workflows/*`, `pubspec.yaml`, `lib/main.dart`, `lib/wear/main_wear.dart` (stub only).
- Do:
  - Add `phone` / `wear` flavors with the same `applicationId`.
  - `src/wear/AndroidManifest.xml` adds `uses-feature android.hardware.type.watch` and `com.google.android.wearable.standalone=true`.
  - Set `uses-feature` `required=false` for `usb.host` and `camera` on the watch.
  - Remove the USB-attached intent filter on the watch.
  - Add the committed dev keystore and wire it into the debug and fallback-release signing.
  - Update `build-app.yml`, `publish-app.yml` and the fastlane AAB path (for example `app-phone-release.aab`). Add a `build-wear-apk` job and add `wear-apk` to the dev and tagged release artifact lists.
  - Build both ABIs by default. Narrow only after 0C reports the watch ABI.
  - `main_wear.dart` stub shows a "Wear OS" screen.
  - Verify the Flutter flavor assumptions: `flutter build apk --flavor phone` still works, and so does a bundle build **[verify]**.
- Tests: CI green for the phone APK and the wear APK, plus `flutter analyze` and `flutter test` unchanged.
- Done when: `wear-apk` is downloadable from the `dev` pre-release on `Ghvinerias/ChameleonUltraGUI`, and the phone and watch APKs carry the same signing cert fingerprint (`apksigner verify --print-certs`).

**0B: Contracts, model move, fakes** (M)
- Owns: `lib/models/**` (new), `lib/core/**` interfaces only, `lib/sync/**` interfaces only, `lib/sharedprefsprovider.dart`, `test/fakes/**`.
- Do:
  - Mechanically move `Dictionary`, `DictionaryFolder`, `CardSave`, `CardFolder` and bundles into `lib/models/`. Re-export from `sharedprefsprovider.dart` so no import elsewhere changes.
  - Add optional `updatedAt` fields (backward-compatible JSON) and a `SyncTombstone` model.
  - Define the interfaces: `ReadService`, `SlotService`, `CardStore`, `DictionaryStore`, `SyncTransport`, `WatchInstaller`.
  - Write `FakeChameleonCommunicator` (scripted cards: MFC 1K default keys, MFC with a custom key, MFU, EM410X, none present) and `InMemorySyncTransport`.
- Tests: existing `card_folder_test.dart` and friends untouched and green. Add legacy-JSON round-trip tests for the new optional fields.
- Done when: the move is behavior-neutral and the interfaces are merged and frozen.

**0C: Hardware spike** (S, needs the watch and a Chameleon; human in the loop)
- An agent prepares a diagnostic screen in `lib/wear/spike/` that logs: ABI and device props, BLE scan/connect/command results, `librecovery.so` load, and timings for darkside, nested and a hardnested run.
- The human installs it (section 5, manual path) and sends back the log.
- Output: `docs/wear-spike-results.md`. Settles D5 and D6 and the ABI question. Also check whether Flutter receives rotary-bezel input **[verify]**.

**0D: Phone installer** (M, starts day 1, continues as T6)
- Owns: `packages/adb_wifi/**`, `lib/installer/**`, a new Settings entry (one added list item in `lib/gui/page/settings.dart`).
- Mini-spike first (1–2 days): compare candidate Kotlin ADB libraries. [adb-kt](https://github.com/rhythmcache/adb-kt) and [Kadb](https://github.com/flyfishxu/Kadb) advertise TLS pairing and install in their READMEs. [dadb](https://github.com/mobile-dev-inc/dadb)'s README does not mention pairing. **None of these is verified against a Galaxy Watch.** Criteria: Android 11+ TLS pairing works, a Wear OS 6 watch accepts it, the license is compatible with GPL-3.0, it is maintained, and ABI support covers the phone.
- Then build the plugin and the wizard (section 5).

### Wave 1

**T1: Core refactor** (L)
- Owns: `lib/core/read/**`, `lib/core/slots/**`, `lib/helpers/general.dart` (the `readHFInfo` region), `lib/helpers/mifare_classic/**`, and the phone read and slot pages for call-site changes only.
- Do:
  - Make `readHFInfo`, `performMifareClassicScan`, `MifareClassicRecovery` and the LF read context-free. Replace localized strings with progress objects (phase, counters, error code). The phone UI maps them to the same strings as today.
  - Extract the slot-upload logic from `slot_manager.dart` into `SlotService.uploadCard` for MFC, MFU, 14a4 and LF.
  - Expose continuous HF and LF scan as streams.
- Tests: characterization tests written first against the current behavior using `FakeChameleonCommunicator`. The refactor must keep them green. Existing `recovery_test.dart` stays green. Add progress-stream tests including cancellation.
- Done when: the phone UI behaves identically, which means no text changes and the same tests pass. Add a manual phone smoke checklist.

**T2: Watch shell and UI kit** (M)
- Owns: `lib/wear/theme/**`, `lib/wear/widgets/**`, `lib/wear/app.dart`, Android rotary channel Kotlin (`android/app/src/wear/**`).
- Do:
  - Round-aware layout: circular clip, edge insets, large tap targets, OLED-black theme, text-scale limits.
  - Navigation: a swipe-dismiss compatible `Navigator`, with a home screen of 6–7 entries (Read, Slots, Saved cards, Dictionaries, Device, Sync, Settings).
  - Reusable widgets: compact list item, 8-slot ring, rotary-driven list, confirm dialog, progress ring, scan animation.
  - Rotary bezel input via a MethodChannel/EventChannel into a `RotaryController`.
- Tests: widget tests plus golden tests at 438×438 inside a circular clip, at text scales 1.0 and 1.3. Goldens are generated on the Linux CI image only.
- Done when: a demo gallery screen shows every widget and the goldens are green.

**T3: Watch connection layer** (M)
- Owns: `lib/wear/connection/**`, additions to `lib/connector/` (a new `serial_wear.dart` only).
- Do:
  - A BLE-only connector (no USB listing, since the watch has no USB host).
  - The Bluetooth permission flow for the watch.
  - Reconnect and keep-alive policy driven by the 0C findings. If Doze or screen-off kills the link, add a foreground service (Kotlin) behind a toggle.
  - Surface connection state for the UI.
- Tests: unit tests over a fake BLE layer for retry, reconnect and permission-denied paths. Manual: connect, screen-off for 1 minute, reconnect.

**T4: Sync engine** (L)
- Owns: `lib/sync/**` (implementations), `lib/models/**` merge helpers.
- Do:
  - Manifest of `(kind, id, updatedAt, hash, size)`, diff, last-writer-wins merge with tombstones (a tombstone wins if `deletedAt > updatedAt`), and a phone-wins tie-break.
  - Chunking and reassembly, SHA-256 integrity (`crypto` is already a dependency), resume by chunk index, atomic apply (stage then commit), and a protocol version handshake.
  - A dictionary mirror mode flag.
- Tests (all on the host VM, no devices):
  - Randomized convergence tests: two replicas, random edits and deletes, sync in both orders, and both end identical.
  - Idempotency: syncing twice changes nothing.
  - Chaos: dropped, duplicated and reordered chunks, interruption and resume, protocol version mismatch.
  - Large payloads (about 5 MB bundle) over `InMemorySyncTransport`.

**T5: `wear_sync` plugin** (M)
- Owns: `packages/wear_sync/**`.
- First day: evaluate [`watch_connectivity`](https://pub.dev/packages/watch_connectivity) (wraps the Wearable APIs per search results) against writing our own. Criteria: bulk payloads of at least 1 MB, Wear OS 6, and maintenance **[verify]**. Fallback is a Kotlin plugin of roughly 400 lines over `play-services-wearable`: message, data item, and channel streams, plus peer discovery.
- Implements `SyncTransport` for real devices.
- Tests: a Kotlin unit test of chunk plumbing. Integration: pair a phone emulator with a Wear emulator (Android Studio pairing) **[verify]** or use real devices, and run a loopback sync test app. A phone without Google Play Services must degrade to "sync unavailable".

**T6: Installer completion** (M, continues 0D)
- See section 5.

**T7: Stores layer** (M)
- Owns: `lib/core/stores/**`, plus call-site edits in `lib/gui/page/saved_cards.dart`, `lib/gui/menu/dialogs/dictionary/**`, `lib/gui/menu/dialogs/card/**`.
- Do:
  - Implement `CardStore` and `DictionaryStore` over SharedPreferences. Every create, update and delete stamps `updatedAt` and writes tombstones.
  - Route all existing phone mutations through them. This is the only track allowed to touch those phone files.
  - File-backed variant only if D6 says so.
- Tests: store unit tests, plus a regression run of the phone card and dictionary flows with fakes.

### Wave 2 (each feature owns its own `lib/wear/screens/<name>/` folder)

| Track | Scope | Depends on |
|---|---|---|
| **F1 Read** | HF and LF single read. Continuous scan with keep-awake (`wakelock_plus`). MFC key-check progress, recovery progress, MFU info. "Save to watch" and "Write to slot". Cancel on back-swipe. | T1, T2, T3 |
| **F2 Saved cards** | Flat or folder list, detail summary, rename, delete, upload to slot (via `SlotService`). | T1, T2, T7 |
| **F3 Slots** | 8-slot view, activate, enable/disable, rename, and slot settings (the features in `gui/menu/dialogs/slot/settings.dart`). | T1, T2, T3 |
| **F4 Device settings** | Animation, button actions, long-press threshold, BLE pairing and key, sleep timeout. No firmware. | T2, T3 |
| **F5 Dictionaries** | List with counts, pick the dictionary used for reads, delete, download from URL (reuse the `http` flow in `dictionary_download.dart`). | T2, T7 |
| **F6 Sync UX** | Watch: status, "Sync now", last result, conflicts summary. Phone: "Watch sync" screen, shown only when a watch peer exists. | T2, T4, T5, T7 |

Each F track adds strings to `lib/l10n/app_en.arb` only, with the prefix `wear_<track>_`. Other locales are Crowdin-managed. Tests per track: widget tests plus goldens against fakes, and one `integration_test` smoke flow on the Wear emulator using the fake communicator.

### Wave 3

- **H1 Hardware matrix:** run section 6 on the real watch and Chameleon. File bugs against owning tracks.
- **H2 Battery, thermal, performance:** 10-minute continuous scan, hardnested run, cold start and memory. Tune or gate features.
- **H3 Release:** signed release APK to the `dev` and tagged releases, install docs, and an optional Play Wear listing later.

---

## 5. Installing the app on the watch from the phone

Three layers, so there is a way in from day 0. The watch has no Play Store flow for sideloaded builds, so every layer relies on **ADB over Wi-Fi (Wireless debugging)**. Wear OS 4 and later support it.

### Layer A: manual, no code (available from Stage 0A)

On the watch:
1. Enable Developer options. The exact tap target varies by One UI Watch version; it is usually tapping the software or build version repeatedly in About watch.
2. Turn on ADB debugging and Wireless debugging.
3. Connect the watch to the same Wi-Fi network as the phone. The watch often has Wi-Fi off, so turn it on explicitly.

On the phone, pick one:
- **Wear Installer 2**, a third-party Play Store app. The AndroidAPS docs describe this workflow: enter the watch IP, choose Pair new, enter the pairing code and port, then install an APK picked on the phone. [Source](https://androidaps.readthedocs.io/nl/latest/WearOS/WearOsSmartwatch.html). I haven't checked that its current version still works on Wear OS 6.
- **Termux** with `android-tools`: `adb pair <ip>:<pairing-port>`, `adb connect <ip>:<port>`, `adb install -r wear.apk` **[verify]**.
- Or a PC with `adb`, if that's easier.

Get the APK from the `wear-apk` artifact of the fork's `dev` pre-release (`https://github.com/Ghvinerias/ChameleonUltraGUI/releases/tag/dev`, zipped).

### Layer B: CI artifact (Track 0A)

A `build-wear-apk` job produces `wear-apk`, attached to the `dev` pre-release as `wear-apk.zip`. It contains `app-wear-release.apk` signed with the shared dev key. This makes the APK fetchable from the phone's browser.

### Layer C: in-app "Install on watch" (Tracks 0D and T6, phone flavor only)

Settings, then Wear OS watch, then Install on watch. A wizard backed by `packages/adb_wifi`:

1. **Checklist screen:** the three watch prerequisites above, with a "same Wi-Fi?" check on the phone side.
2. **Pair:** the user types the watch IP and pairing port plus the 6-digit code from the watch's Wireless debugging screen. The plugin runs the TLS pairing and stores the ADB key pair in app-private storage.
3. **Connect:** the user enters the watch's connect IP and port. This port is different from the pairing port and changes whenever Wireless debugging is toggled. Optional later: mDNS auto-discovery via `NsdManager` for `_adb-tls-connect._tcp`.
4. **APK source:** (a) download the latest `wear-apk.zip` from the configured release URL (extract with the `archive` dependency, following the `http` pattern in `lib/helpers/github.dart`), or (b) pick a local APK with `file_picker`.
5. **Install and launch:** `adb install -r`, then launch the activity, with a progress UI.
6. **Aftercare:** a reminder to turn Wireless debugging off, and a "Forget watch" button that deletes the stored keys.

Error mapping, each with a user-facing hint:

| Error | Hint |
|---|---|
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Signature mismatch. Offer to uninstall and retry. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | ABI mismatch. Rebuild both ABIs. |
| Connection refused or timeout | Check watch Wi-Fi, the port, and that wireless debugging is still on. |
| Pairing failed | Re-pair. The code expires and the pairing port changes. |

Tests:
- Unit: the wizard state machine against `FakeAdb` for every error path above.
- Plugin: a Kotlin unit test of the install-command and error-parsing logic.
- Manual on the real watch, as the Wave 1 gate G1 check: pair, connect, install, update in place (same signature), and the wrong-signature path.

Security notes: the ADB private key never leaves app storage. The pairing code is user-entered and used once. The feature only talks to an IP the user typed. It does not run on non-Android platforms and is hidden in the `wear` flavor.

Open decision: whether to ship Layer C in the public phone build or behind Developer mode only. I recommend Developer mode only (the app has a `devMode` flag) until the feature has proven reliable.

---

## 6. Test strategy

| Level | What | Where it runs |
|---|---|---|
| Unit | Sync merge, chunking, stores, services (via `FakeChameleonCommunicator`), installer state machine | `flutter test`, Linux CI |
| Existing | Native recovery tests, card folder, firmware artifact, key-check, sniff parsers | `flutter test` (needs the built native lib, as today) |
| Widget and golden | Watch screens at 438×438, circular clip, text scale 1.0 and 1.3 | `flutter test`, Linux CI image |
| Integration | `integration_test` smoke flows on the Wear emulator with the emulated device (`--dart-define` switch) | Local emulator. CI only if Wear emulators are viable in CI **[verify]** |
| Sync integration | Phone and watch pair with the real plugin | Paired emulators **[verify]** or real devices |
| Phone regression | Phone read and slot flows unchanged after T1 and T7 | Characterization tests plus a manual smoke checklist |
| Hardware matrix | Needs the real watch and Chameleon (BLE cannot be emulated) | Manual, section below |

Hardware matrix (H1), on a Chameleon Ultra and a Chameleon Lite:
- Connect, disconnect and reconnect, and screen-off during a connection.
- MFC 1K with default keys, with a key in a custom dictionary, and with a darkside-vulnerable card.
- A nested-attack card, a static-nested card and (if D5 allows) hardnested.
- MFU / NTAG215 read.
- LF EM410X and HID, and a continuous HF and LF scan for 10 minutes.
- Save to watch, upload to slot, slot activation, and each device setting.
- Sync: add a card on the watch and see it on the phone, edit on the phone and see it on the watch, delete both ways, and an interrupted sync.

CI additions (0A): `flutter analyze`, `flutter test` on Linux for the new code, and the wear APK build. The existing Windows and Linux jobs stay as they are.

---

## 7. Build and run reference

```bash
cd chameleonultragui
flutter pub get
flutter analyze && flutter test

# phone
flutter build apk --flavor phone --build-number <N>

# watch (fat APK until 0C reports the ABI; then optionally --target-platform android-arm64)
flutter build apk --flavor wear -t lib/wear/main_wear.dart --build-number <N>
# output: build/app/outputs/flutter-apk/app-wear-release.apk   [verify exact name]

# dev loop on the watch over wireless debugging
adb pair <ip>:<pairing-port>
adb connect <ip>:<port>
flutter run --flavor wear -t lib/wear/main_wear.dart -d <ip>:<port>
```

Note: this machine currently has no Flutter SDK and no `adb`. Agents running locally need a Flutter stable toolchain (the pubspec requires Dart ^3.13 and Flutter ≥3.47), JDK 21, and the Android SDK and NDK 28.2 before they can run any command above. CI is the fallback verifier.

---

## 8. Parallel execution protocol

1. Create the integration branch `feat/wear-os` off `main`. Each track works in its own git worktree on `wear/<track>`, and opens PRs into `feat/wear-os`.
2. File ownership is the conflict-avoidance rule (the "Owns" lists). Shared hot files:
   - `lib/main.dart`, `pubspec.yaml`, `android/**`: only 0A touches them. Others ask 0A (or the human) for changes.
   - `lib/sharedprefsprovider.dart`: only 0B (the move) and then T7.
   - `lib/l10n/app_en.arb`: any track may append keys with its own `wear_<track>_` prefix. Resolve rebase conflicts by keeping both sides.
   - Phone UI files: T1 (read and slot pages) and T7 (cards and dictionaries) only.
3. Merge order within a wave: tracks merge as they finish, but anything labelled `contract-change` merges first and the rest rebase.
4. Every PR must pass `flutter analyze`, `flutter test`, and both APK builds before merge.
5. Agent brief template (each agent gets): the track section above, the contract files to read first, its file ownership list, the test requirements, "done when", and the rule that it must not edit files outside its ownership without asking.
6. Human checkpoints: G0 (spike on the real watch), G1 (installer plus sync on real devices), G2 and G3 (hardware passes). Everything else can run unattended.

---

## 9. Timeline and risks

Rough calendar with 4–6 concurrent agents, bounded by review and hardware sessions rather than coding speed:

| Phase | Calendar |
|---|---|
| Stage 0 | about 1 week |
| Wave 1 | 2–3 weeks |
| Wave 2 | 2–3 weeks |
| Wave 3 | about 2 weeks |
| **Total** | **7–10 weeks** |

The critical path is 0A, then 0C, then T1, then F1, then H1. The effort is the same ~13–17 person-weeks estimated earlier, compressed by running tracks in parallel. These are estimates, not commitments.

| Risk | Impact | Mitigation |
|---|---|---|
| BLE unstable on the watch | Project blocker | 0C spike before any investment. T3 reconnect and keep-alive. |
| Watch ABI is 32-bit only (armeabi-v7a) **[verify]** | Install failure | 0A builds both ABIs. 0C reports the ABI. |
| ADB library does not work with Wear OS 6 pairing | Layer C slips | Layers A and B work regardless. 0D evaluates two libraries. |
| Signing mismatch | Sync and upgrades fail | D3, checked in CI with `apksigner`. |
| Phone regression from T1 and T7 refactors | Broken main app | Characterization tests first, `feat/wear-os` isolation, smoke checklist. |
| Hardnested too heavy for the watch | One feature cut | D5 gate. MFC still reads through dictionary, darkside and nested. |
| SharedPreferences too slow with big data | Slow startup | D6, file-backed stores. |
| Rotary bezel not delivered to Flutter **[verify]** | No bezel scrolling | T2 Kotlin channel. Touch scrolling works regardless. |
| GMS dependency added to the phone APK | Breaks non-GMS phones | T5 degrades to "sync unavailable". |

Sources used for the research claims:
- [AndroidAPS Wear OS setup (Wear Installer 2 workflow)](https://androidaps.readthedocs.io/nl/latest/WearOS/WearOsSmartwatch.html)
- [adb-kt](https://github.com/rhythmcache/adb-kt), [Kadb](https://github.com/flyfishxu/Kadb), [dadb](https://github.com/mobile-dev-inc/dadb)
- [watch_connectivity on pub.dev](https://pub.dev/packages/watch_connectivity)
