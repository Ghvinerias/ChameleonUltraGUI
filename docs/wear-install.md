# Installing the Wear OS app on the watch

Dev builds (the ones from CI without the real keystore, and local debug builds) install as **`io.chameleon.ultra.dev`** with the label **"CU GUI Dev"**. They sit beside the Play Store app (`io.chameleon.ultra`) and keep separate data, so installing them never touches your existing cards or settings. Phone and watch dev builds share the package name and signing key, which the phone <-> watch sync requires. The watch runs a 32-bit process; the watch APK includes `armeabi-v7a`.

Status: the in-app wizard (Track 0D) is implemented and unit tested, but **has not been tested on a real watch**. Everything about Galaxy Watch / Wear OS 6 behaviour below is unverified unless stated otherwise.

All paths use **ADB over Wi-Fi (Wireless debugging)**, which Wear OS 4 and later offer in Developer options.

## 0. Prepare the watch (all methods)

1. Enable Developer options. Usually: Settings > About watch > Software information, then tap "Software version" (or "Build number") about 7 times. The exact menu differs between One UI Watch versions.
2. Settings > Developer options: turn on **ADB debugging** and **Wireless debugging**.
3. Put the watch on the **same Wi-Fi network as the phone** and make sure the watch's Wi-Fi is **on**; it is often off to save battery.
4. Open Wireless debugging. It shows `IP address & Port` (connect port). "Pair new device" shows a 6-digit code plus a different pairing IP/port.

Get the APK: `wear-apk.zip` on the `dev` pre-release,
`https://github.com/Ghvinerias/ChameleonUltraGUI/releases/download/dev/wear-apk.zip` (contains a directory with the `.apk`).

## 1. In-app wizard (phone app)

Hidden unless **debug/developer mode** is on (Settings > Activate debug mode). Then Settings > **Install on watch** (Android phones only).

Steps:

1. **Checklist** of the prerequisites above.
2. **Pair**: enter the watch IP, the *pairing* port and the 6-digit code. The phone does the Android 11+ TLS pairing. The code is used once and not stored. Use "Already paired, skip" if you paired before.
3. **Connect**: enter the IP and the *connect* port from the main Wireless debugging screen. This port changes each time Wireless debugging is toggled. The wizard also shows the installed app version on the watch, if any.
4. **APK source**: download the latest `wear-apk.zip` (URL is editable) or pick a local `.apk`.
5. **Install**: `install -r` (updates in place if the signature matches), with a progress bar.
6. **Launch** the app on the watch, then **aftercare**: switch Wireless debugging off again. **Forget watch** (also in the app bar) deletes the phone's ADB key.

Errors and hints:

| Error | Meaning / what to do |
|---|---|
| Signature mismatch (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) | The watch has the app signed with another key. The wizard offers "Uninstall old app and retry" (removes the app's data). |
| No matching ABIs (`INSTALL_FAILED_NO_MATCHING_ABIS`) | The APK lacks native code for the watch CPU. Use a build with both ABIs. |
| Connection refused / timeout | Watch Wi-Fi off, wrong IP/port, or Wireless debugging turned off/changed port. |
| Pairing failed | Code expired or wrong, pairing port changed, or the phone key is no longer trusted: pair again. |

Security: the ADB private key is generated on the phone and stored in the app's private storage (`files/adb_wifi/adbkey.pem`); it is never exported. The feature only talks to the IP address you type and has no background component.

## 2. Manual fallbacks

### Wear Installer 2 (Android app)

Third-party Play Store app. The AndroidAPS documentation describes the workflow: enter the watch IP, choose "Pair new", enter pairing code and port, then install an APK chosen on the phone.
Source: https://androidaps.readthedocs.io/nl/latest/WearOS/WearOsSmartwatch.html
**Not verified to still work on Wear OS 6.**

### Termux with android-tools on the phone

```sh
pkg install android-tools
adb pair <watch-ip>:<pairing-port>      # enter the 6-digit code
adb connect <watch-ip>:<connect-port>
adb install -r app-wear-release.apk
```
**Unverified** (not run here).

### PC with adb

```sh
adb pair <watch-ip>:<pairing-port>
adb connect <watch-ip>:<connect-port>
adb install -r app-wear-release.apk
```
Needs a recent platform-tools (Android 11+ pairing support).
