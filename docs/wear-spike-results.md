# Wear OS spike results (Gate G0)

Filled in by the lead from the JSON report (sent as QR codes or POSTed to `/report`). `TBD` = not yet measured.

## Gate G0 criteria

Source: report `bb4f4467` (decoded from the QR frames), run 2026-10-27, Galaxy Watch 8 Classic.

| Criterion | Result | Evidence / notes |
|---|---|---|
| App installs on the watch (sideload path) | **Pass** | Installed and ran (the user installed the placeholder and spike builds) |
| Process ABI (arm64 vs arm 32-bit) | **32-bit: `android_arm`** | `device_info.abi`; Dart VM reports `android_arm`. The watch APK MUST ship `armeabi-v7a`; an arm64-only build would not run |
| BLE permissions granted | Pass | `ble_permissions`: scan + connect granted |
| BLE scan finds the Chameleon | Pass | `ble_scan`: found 1 (`Ultra F5:D4:E1:AA:D2:08`) in 2.0 s |
| BLE connect | Pass | `ble_connect`: 819 ms |
| Command round trip (firmware, battery, mode, slot) | Pass | firmware version 514 (0x202), battery 65% / 3940 mV, mode `emulator`, active slot 6; 55-86 ms each |
| HF scan returns cleanly with no card | Pass | `chameleon_hf_scan`: 57 ms, no hang |
| 20-command latency (min/avg/p95/max ms) | 57 / 71 / 95 / 98 | `chameleon_latency_20` |
| Connection survives screen off (90 s keep-alive) | **Pass** | `ble_keepalive`: 18/18 ok over 103 s; max gap between queries 18.2 s (5 s timer was throttled while asleep, no drops) |
| Native library loads | Pass | `recovery_load`: `librecovery.so` (armeabi-v7a build) |
| Darkside / nested / static encrypted nested timings | 4.2 s / 6.5 s / 0.6 s | all found the expected key |
| Hardnested completes (time, memory) | **Crashed the app** | Reported by the user after tapping Hardnested on the watch (no crash log or QR report available). Likely cause, from reading `src/hardnested.c` (not measured): `nonces[256]` allocates and fills two 2 MB bitarrays per entry (256 x 2 x 2 MB = about 1 GiB) at init, plus about 150 MB of sum tables, against about 605 MB available. That is either an OOM kill or the `exit(4)` after a failed allocation |
| Rotary bezel reaches Flutter | **Only via the native channel** | Flutter pointer/key events: 0. Native `MainActivity` channel: 133 events, delta sum 59.0 (the user rotated the bezel) |
| SharedPreferences cost at 0 and 5 MB | Fine | `storage_timing`: getInstance 0 ms, reload empty 3 ms, write 5 MB 393 ms, reload 5 MB 85 ms |
| Cold start to first frame | 33 ms (main to first frame) | process age not readable (`/proc/uptime` denied) |
| Watch reaches the LAN receiver | Pass this time | `network`: `GET /health` -> 200 in 2.5 s |

Decision: **go**, with hardnested **phone-only** (D5 resolved by the crash above). Findings that change the plan:
- **The watch is a 32-bit environment.** Keep `armeabi-v7a` in the watch flavor. Never ship arm64-only. A v7a-only watch build would be about half the size.
- **Design for about 206 x 206 dp**, not 438: the screen is 438 px at devicePixelRatio 2.125.
- **Memory is tight:** MemTotal 1.89 GB, MemAvailable about 605 MB with the spike running. Hardnested needs about 1.2 GB at init and crashed the app, so it stays phone-only. The watch keeps dictionary check, darkside, nested and static-encrypted-nested, which all ran. A possible later option: the watch collects hardnested nonces and the phone cracks them over the sync channel.
- **BLE is solid enough** for the whole feature set (0.8 s connect, about 70 ms per command, survives screen-off).
- **Bezel:** the T2 native rotary channel is validated; Flutter's own pointer path is not used by the Classic bezel.
- **D6:** SharedPreferences is fine at 5 MB, so no file-backed store is needed for the MVP.

## Device

| Field | Value |
|---|---|
| Watch / OS | Galaxy Watch 8 Classic, build `BP2A.250325.020.L500XXS2AZF4`, Wear OS 6 / Android 16 (inferred from the build id; not read from the API) |
| ABI | `android_arm` (32-bit), 5 processors |
| Screen (px, DPR, round?) | 438 x 438 px, DPR 2.125 -> 206 x 206 dp; roundness not reported by Flutter (no insets) |
| Free memory (MemAvailable) | 605 MB of 1.89 GB total (spike app running) |

## How to run the spike

Build: `flutter build apk --flavor wear -t lib/wear/main_wear.dart` (output `build/app/outputs/flutter-apk/app-wear-release.apk`), then install it on the watch (docs/wear-install.md). Package `io.chameleon.ultra.dev`.

Preparation:
- The receiver must be running at `http://10.10.10.24:8001` (`GET /health` returns `ok`), and the watch must be on the same network (Wi-Fi on, not only phone-proxied Bluetooth).
- The Chameleon must be powered on, BLE enabled, and NOT connected to a phone.
- Open the app and grant the Bluetooth permissions when asked. Each entry is a big button on the launcher; scroll with a finger.

Order (about 6 minutes in total):
1. **Device info** > Collect (instant).
2. **Rotary / bezel**: open the screen, rotate the bezel exactly 10 clicks/turns clockwise, then 10 counter-clockwise. Note the number you rotated and the counters shown. Tap "Save result".
3. **Network** > GET /health (a few seconds).
4. **Storage timing** > Run (a few seconds; writes and removes 5 MB).
5. **BLE + Chameleon**: "1. Permissions + scan" (about 5 s, grant permissions), then tap the Chameleon button ("2. Connect ...", up to 90 s), which runs the firmware, battery, mode, slot, HF scan and 20-command latency checks automatically.
6. **Keep-alive** (still connected): tap "3. Start 90 s keep-alive test", then press the watch crown or lower your wrist so the screen turns off and **leave it asleep for the full 90 s**. Wake it and read "keep-alive: ok/total". A healthy run is 18/18.
7. **Native recovery**: "1. Load + darkside/nested" (seconds), then "2. Hardnested" (up to 120 s). Keep the app open. If the watch kills the app, relaunch it: the launcher shows "Previous run did not finish hardnested", and the earlier results are in the saved file; just send a report from the relaunched app after re-running the quick checks.
8. **Report**: check the URL (default `http://10.10.10.24:8001/report`; it is remembered between launches), tap "Send report". The same JSON is also written to the app cache dir (`wear_spike_report.json`).

Tell the lead: how many times you rotated the bezel, whether the screen really turned off during the keep-alive, and anything that crashed.
