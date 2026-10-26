# Kotlin/JVM ADB client library evaluation (Track 0D mini-spike)

Date: 2026-10-26. Evaluated from README, source (shallow clones of each default branch), GitHub release/metadata API and Maven Central metadata.

**No Galaxy Watch or other Wear OS device was available. Nothing below was tested against real hardware; ratings are from code evidence only.** Claims I could not verify are marked **[unverified]**.

## Candidates

| | **Kadb** (`flyfishxu/Kadb`) | **adb-kt** (`rhythmcache/adb-kt`) | **dadb** (`mobile-dev-inc/dadb`) |
|---|---|---|---|
| 1a. Android 11+ TLS **pairing** (code + pairing port) | Yes: `Kadb.pair(host, port, code)`. SPAKE2 (`spake2-java`), TLS 1.3 exporter via platform Conscrypt (reflection + `HiddenApiBypass`) on Android 10+; needs custom Conscrypt below Android 9 | Yes: `AdbClient.pairTls(host, port, code, keyProvider)`. SPAKE2 + BouncyCastle TLS (does not depend on platform Conscrypt) | **No.** No pairing code in `dadb/src/main` (the only "pair" hits are in tests/key-pair code); README and CHANGELOG never mention it |
| 1b. TLS **connect** (Wireless debugging port, `STLS`) | Yes, `TlsNioChannel` / `Kadb.create(host, port)` negotiates STLS | Yes, `AdbClient.connectTls` | Plain TCP + AUTH only; TLS-only wireless-debugging connect is not implemented **[unverified, no TLS code found by grep]** |
| 2. APK install + progress | `install(File/Source, size, opts)`: streaming `cmd package install -S`, falls back to push + `pm install`. **No progress callback**, throws `IllegalStateException("Install failed: …")` (message carries the `INSTALL_FAILED_*` code). Progress is obtainable by wrapping the okio `Source` (done in our plugin) | `AdbInstall.install(file): Flow<InstallProgress>` (bytes/percent built in). Failure throws `AdbException.Protocol("Installation failed: …")` | `install()` returns `InstallResult`, no progress |
| 3. License vs GPL-3.0 | Apache-2.0 (one-way compatible with GPL-3.0). Deps: BouncyCastle (MIT), okio/coroutines (Apache), `spake2-java` **[license unverified]**, `hiddenapibypass` (Apache-2.0) | Apache-2.0. Deps: BouncyCastle, okio, `spake2-kt` **[license unverified]** | Apache-2.0 |
| 4. Maintenance (as of 2026-10-26) | Last push 2026-10-24, releases 2.1.3 (07-17) → 2.1.4 (09-04) → 2.1.5 (10-15). 107 stars, 8 open issues. Used by the vendor's own "WearOS Toolbox" app (claim from its README, **[unverified]** externally) | Last push 2026-09-20, v1.0.6 (08-21). 2 stars, 1 open issue; young project (copyright 2026), almost no field use | Last push 2026-06-22, 1.2k stars, 32 issues; solid but pairing never added |
| 5. Gradle distribution / ABI / minSdk | **Maven Central** `com.flyfishxu:kadb:2.1.5` (published with an `android` variant; verified in the `.module` file). Pure Kotlin, no native libs (ABI-agnostic). minSdk 23. Built with Kotlin 2.4.20 (the app already uses 2.4.20), AGP 9.4, compileSdk 37 (**risk: consumed from an AGP 8.13 app, see "Build result"**). Transitively pulls `com.github.Flyfish233:spake2-java` from **JitPack** | Published for **JitPack only** (`com.github.rhythmcache:adb-kt`; the README's `io.github.rhythmcache` coordinate is **not** on Maven Central, checked). The module is plain `kotlin("jvm")` (JDK 17 target), not an Android library; minSdk 24 per README **[unverified]** | Maven Central `dev.mobile:dadb:2.0.0`, no native libs |
| 6. App-private key storage | `KadbCert.configure(OkioFilePrivateKeyStore(path))`: we point it at `filesDir`; `KadbCert.clear()` deletes (supports Forget watch). Private key only is persisted | `FileKeyProvider(file)` / `MemoryKeyProvider`; PEM/DER; plus a `PairedDeviceStore` | `AdbKeyPair.read(file)` |

## Other libraries seen

- `MuntashirAkon/libadb-android` (Java, **GPL-3.0 / Apache-2.0 dual**, per its README **[unverified]**): older, pairing + connect, widely used by Shizuku-like apps. Needs Conscrypt. Not evaluated in depth; it is the natural fallback if Kadb fails to link.
- `Flyfish233/spake2-java`: only the SPAKE2 piece.

## Recommendation

**Primary: Kadb (2.1.1 pinned for now, see build result).** It is the only candidate that has all of: TLS pairing + TLS connect, Maven Central publication with a proper Android variant, active releases, an API for removing the stored key, and a Wear OS-focused downstream user. Progress is not built in, but wrapping the `Source` is trivial.

**Fallback 1: adb-kt** (best install-progress API and its own BouncyCastle TLS stack, which avoids the hidden-API/Conscrypt reflection that Kadb needs on Android), but it is tiny, JitPack-only and not an Android library.
**Fallback 2: libadb-android.**
**Rejected: dadb** (no pairing, no wireless-debugging TLS).

## Build result (verified)

- `com.flyfishxu:kadb:2.1.5` **does not build** in this project: its AAR metadata requires `compileSdk >= 37`, but the app is pinned to AGP 8.13.2 / compileSdk 36 (`checkDebugAarMetadata` fails; also true for 2.1.2–2.1.4).
- **`kadb:2.1.1`** (AAR `minCompileSdk=36`) resolves, compiles and links: `flutter build apk --debug` succeeds, the dex contains `AdbWifiPlugin` and Kadb classes, and the plugin's Kotlin unit tests (`:adb_wifi:testDebugUnitTest`) pass. The plugin therefore pins **2.1.1**. Move to the latest Kadb once the project moves to compileSdk 37 / a newer AGP. 2.1.1 lacks the fixes from 2.1.2–2.1.5 (changelog not reviewed, **[unverified]** what they fix).
- adb-kt and dadb were not built.

## Risks that remain open

1. Pairing on a Wear OS 6 / One UI Watch 8 watch **[unverified]**. Samsung's wireless-debugging flow is believed to follow AOSP (`_adb-tls-pairing._tcp`, 6-digit code); both libraries implement the AOSP protocol, but neither is tested here against a Galaxy Watch.
2. Kadb's Android pairing relies on `HiddenApiBypass` to reach `com.android.org.conscrypt.Conscrypt` for the TLS key-material exporter. A future Android release could break this.
3. `spake2-java` comes from JitPack, so the build needs `maven { url 'https://jitpack.io' }` and is exposed to JitPack availability.
4. Install-error reporting is string based (`INSTALL_FAILED_…` inside exception text); we parse it (unit tested).
5. Android 12+ phantom-process / battery restrictions are irrelevant (no background process), but the watch may disable Wireless debugging when it leaves Wi-Fi or sleeps **[unverified]**.
