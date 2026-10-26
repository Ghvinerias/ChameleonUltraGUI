import '../watch_installer.dart';

/// Hardcoded English strings for the watch installer (l10n integration comes later).
class InstallerStrings {
  static const entryTitle = 'Install on watch';
  static const entrySubtitle =
      'Developer: install the Wear OS app over Wi-Fi (ADB)';
  static const pageTitle = 'Install on watch';

  static const checklistTitle = 'Prepare your watch';
  static const checklistIntro =
      'The phone installs the watch app over ADB wireless debugging. Do these on the watch first:';
  static const checklistDevOptions =
      'Enable Developer options: Settings > About watch > Software information, then tap "Software version" (or "Build number") about 7 times. The exact menu differs between One UI Watch versions.';
  static const checklistAdb =
      'In Settings > Developer options, turn on "ADB debugging" and "Wireless debugging".';
  static const checklistWifi =
      'Put the watch on the same Wi-Fi network as this phone, and make sure the watch\'s Wi-Fi is ON (it is often switched off to save battery).';
  static const checklistPairHint =
      'Then open Wireless debugging > "Pair new device". The watch shows a pairing code, an IP address and a pairing port.';
  static const checklistConfirm = 'I did all of this';

  static const pairTitle = 'Pair with the watch';
  static const pairIntro =
      'Enter the IP address, pairing port and 6-digit code shown on the watch under "Pair new device". The code is used once and is not stored.';
  static const hostLabel = 'Watch IP address';
  static const pairPortLabel = 'Pairing port';
  static const pairCodeLabel = 'Pairing code';
  static const pairButton = 'Pair';
  static const alreadyPaired = 'Already paired, skip';

  static const connectTitle = 'Connect to the watch';
  static const connectIntro =
      'Close the pairing screen. On the main Wireless debugging screen the watch shows "IP address & Port". That port is different from the pairing port and changes each time Wireless debugging is switched on.';
  static const connectPortLabel = 'Connect port';
  static const connectButton = 'Connect';

  static const apkTitle = 'Choose the watch app';
  static String installedVersion(WatchPackageVersion? v) => v == null
      ? 'The app is not installed on the watch yet.'
      : 'Installed on the watch: ${v.versionName ?? '?'} (${v.versionCode ?? '?'})';
  static const downloadButton = 'Download latest build';
  static const urlLabel = 'Release URL (wear-apk.zip)';
  static const pickButton = 'Pick a local .apk';

  static const installTitle = 'Install';
  static String installReady(String name) =>
      'Ready to install $name on the watch (existing installs are updated in place).';
  static const installButton = 'Install';
  static const installing = 'Installing... keep the watch awake and nearby.';
  static const uninstallRetry = 'Uninstall old app and retry';
  static const uninstallWarning =
      'This removes the Chameleon app and its data from the watch.';

  static const launchTitle = 'Installed';
  static const launchIntro = 'The app is on the watch. Open it now?';
  static const launchButton = 'Open on watch';
  static const skipButton = 'Skip';

  static const aftercareTitle = 'Done';
  static const aftercareText =
      'Remember to turn Wireless debugging off on the watch when you are finished (Settings > Developer options). It keeps the Wi-Fi radio busy and drains the battery.';
  static const closeButton = 'Close';
  static const forgetButton = 'Forget watch';
  static const forgetConfirm =
      'Deletes this phone\'s ADB key. The watch will ask for pairing again next time. Continue?';
  static const forgotten = 'Watch forgotten. The stored ADB key was deleted.';
  static const back = 'Back';
  static const cancel = 'Cancel';
  static const ok = 'OK';
  static const invalidInput = 'Enter a valid IP address, port and code.';

  static String errorTitle(WatchInstallErrorType t) => switch (t) {
    WatchInstallErrorType.signatureMismatch => 'Signature mismatch',
    WatchInstallErrorType.noMatchingAbis => 'Incompatible CPU architecture',
    WatchInstallErrorType.connectionFailed => 'Could not reach the watch',
    WatchInstallErrorType.pairingFailed => 'Pairing failed',
    WatchInstallErrorType.notConnected => 'Not connected',
    WatchInstallErrorType.downloadFailed => 'Download failed',
    WatchInstallErrorType.invalidApk => 'Not an APK',
    WatchInstallErrorType.other => 'Something went wrong',
  };

  static String errorHint(WatchInstallErrorType t) => switch (t) {
    WatchInstallErrorType.signatureMismatch => 'The watch already has this app signed with a different key (INSTALL_FAILED_UPDATE_INCOMPATIBLE). Uninstall the old app and retry, or install a build signed with the same key.',
    WatchInstallErrorType.noMatchingAbis => 'The APK contains no native code for this watch (INSTALL_FAILED_NO_MATCHING_ABIS). Use a build that includes the watch\'s CPU architecture (a build with both ABIs).',
    WatchInstallErrorType.connectionFailed => 'Check that the watch Wi-Fi is on and on the same network, that the IP and port are right, and that Wireless debugging is still on. The connect port changes whenever Wireless debugging is toggled.',
    WatchInstallErrorType.pairingFailed => 'Re-pair: the code expires and the pairing port changes every time the "Pair new device" screen is opened. If connecting says the phone is not trusted, pair again.',
    WatchInstallErrorType.notConnected =>
      'The connection to the watch was lost. Go back and connect again.',
    WatchInstallErrorType.downloadFailed => 'Check the phone\'s internet connection and the release URL, or pick a local .apk instead.',
    WatchInstallErrorType.invalidApk => 'Pick a file that ends in .apk.',
    WatchInstallErrorType.other =>
      'See the technical details below. You can retry or go back a step.',
  };
}
