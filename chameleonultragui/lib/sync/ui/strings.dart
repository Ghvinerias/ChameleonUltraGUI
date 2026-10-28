// English strings for the phone <-> watch sync screens (shared by the phone
// page and the watch screen). Kept out of the .arb files on purpose.
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_errors.dart';
import 'package:chameleonultragui/sync/sync_types.dart';
import 'package:chameleonultragui/sync/ui/sync_check.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';

class SyncStrings {
  SyncStrings._();

  // phone
  static const phoneEntryTitle = 'Watch sync';
  static const phoneEntrySubtitle =
      'Sync cards and dictionaries with the watch';
  static const phonePageTitle = 'Watch sync';
  static const syncNow = 'Sync now';
  static const cancel = 'Cancel';
  static const mirrorTitle = 'Mirror dictionaries to watch';
  static const mirrorSubtitle =
      'The watch gets exactly the phone\'s dictionaries. Dictionaries that '
      'exist only on the watch are removed.';
  static const phoneHowTo =
      'Open the Sync screen on the watch, then tap "Sync now". Both apps must '
      'be open while syncing.';

  // status
  static const peerStarting = 'Starting';
  static const peerAvailablePhone = 'Watch connected';
  static const peerUnavailable = 'Not connected';
  static const peerUnavailableHintPhone =
      'Open the Chameleon Ultra app on the watch and check it is paired.';

  static String unsupportedTitle(SyncUnsupportedReason r) => switch (r) {
    SyncUnsupportedReason.notAndroid => 'Sync unavailable',
    SyncUnsupportedReason.noPlayServices => 'No Play Services',
  };

  static String unsupportedBody(SyncUnsupportedReason r) => switch (r) {
    SyncUnsupportedReason.notAndroid =>
      'Watch sync only works on Android phones.',
    SyncUnsupportedReason.noPlayServices =>
      'Watch sync needs Google Play Services (Wear OS Data Layer), which is '
          'missing or disabled on this device.',
  };

  // progress / result
  static String phaseLabel(SyncPhase p) => switch (p) {
    SyncPhase.connecting => 'Connecting',
    SyncPhase.exchangingManifests => 'Comparing',
    SyncPhase.transferring => 'Transferring',
    SyncPhase.verifying => 'Verifying',
    SyncPhase.committing => 'Saving',
    SyncPhase.done => 'Done',
  };

  static const libraryTitle = 'On this device';
  static const lastResultTitle = 'Last sync';
  static const lastFailureTitle = 'Last sync failed';
  static const noChanges = 'Everything was already up to date.';
  static const changesHere = 'Changed on this device';
  static const changesOther = 'Changed on the other device';
  static const nothing = 'nothing';

  static String kindLabel(SyncEntityKind k) => switch (k) {
    SyncEntityKind.card => 'Cards',
    SyncEntityKind.cardFolder => 'Card folders',
    SyncEntityKind.dictionary => 'Dictionaries',
    SyncEntityKind.dictionaryFolder => 'Dict. folders',
  };

  static String counts(int added, int updated, int deleted) =>
      '+$added  ~$updated  -$deleted';

  static String conflicts(int n) =>
      n == 1 ? '1 conflict resolved' : '$n conflicts resolved';

  static String orphans(int n) =>
      n == 1 ? '1 item moved to root' : '$n items moved to root';

  static String bytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static String duration(Duration d) => d.inMilliseconds < 1000
      ? '${d.inMilliseconds} ms'
      : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

  static String sizeLine(int sent, int received) =>
      'Sent ${bytes(sent)}, received ${bytes(received)}';

  /// Human-readable text for a failed sync (never exposes `message`).
  static String errorMessage(SyncException e) => switch (e.code) {
    SyncErrorCode.peerUnavailable =>
      'The other device is not reachable. Open the app on both devices and '
          'try again.',
    SyncErrorCode.versionMismatch =>
      e.localVersion != null && e.peerVersion != null
          ? 'The apps use different sync versions (this device '
                '${e.localVersion}, other ${e.peerVersion}). Update the app '
                'on the older device.'
          : 'The apps use different sync versions. Update the app on the '
                'older device.',
    SyncErrorCode.cancelled =>
      e.fromPeer
          ? 'The other device cancelled the sync. Nothing was changed.'
          : 'Sync cancelled. Nothing was changed.',
    SyncErrorCode.integrityFailure =>
      'Data was damaged in transit. Nothing was changed; try again.',
    SyncErrorCode.transportLost =>
      'The connection to the other device was lost. Nothing was changed; '
          'try again.',
    SyncErrorCode.timeout =>
      'The other device stopped responding. Nothing was changed; try again.',
    SyncErrorCode.dataChanged =>
      'Data changed while syncing. Nothing was changed; try again.',
    SyncErrorCode.protocol =>
      'The other device sent something unexpected. Update both apps and try '
          'again.',
    SyncErrorCode.storeFailure =>
      'Saving failed on a device. Changes were rolled back where possible.',
  };

  // sync check
  static const checkTitle = 'Sync check';
  static const checkRun = 'Run check';
  static const checkRunning = 'Checking';
  static const checkHowTo =
      'Tests the link: ping, then 1 MB each way with an integrity check. '
      'Open the Sync screen on both devices, then run the check on either.';
  static const checkPass = 'PASS';
  static const checkFail = 'FAIL';
  static const checkPing = 'Ping';
  static const checkSend = 'Send 1 MB';
  static const checkReceive = 'Receive 1 MB';
  static const checkSkipped = 'skipped';

  static String stageLabel(SyncCheckStage s) => switch (s) {
    SyncCheckStage.ping => 'Ping',
    SyncCheckStage.send => 'Sending 1 MB',
    SyncCheckStage.receive => 'Receiving 1 MB',
  };

  static String pingLine(SyncCheckResult r) => r.pingOk
      ? 'avg ${(r.pingAverage.inMicroseconds / 1000).toStringAsFixed(1)} ms '
            '(${r.pingSamples} pings)'
      : (r.pingError ?? 'failed');

  static String transferLine(SyncCheckTransfer t) {
    if (t.skipped) return checkSkipped;
    if (!t.ok) return t.error ?? 'failed';
    return '${bytes(t.bytes)} in ${duration(t.elapsed)}, '
        '${(t.bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
}
