// English strings of the watch Sync screen (not in the .arb files on purpose).
// Shared sync strings (errors, phases, check) live in lib/sync/ui/strings.dart.
class WatchSyncStrings {
  WatchSyncStrings._();

  static const title = 'Sync';
  static const waitingForPhone = 'Waiting for phone';
  static const howTo =
      'Start the sync on the phone: Settings > Watch sync > Sync now. Keep '
      'this screen open. The watch cannot start a sync itself.';
  static const mirrorNote = 'Mirror mode is chosen on the phone.';
  static const phoneConnected = 'Phone connected';
  static const peerUnavailableHint =
      'Open the Chameleon Ultra app on the phone and check the watch is '
      'paired.';
  static const syncing = 'Syncing';
  static const checkHowTo =
      'Tests the link: ping, then 1 MB each way. Open Watch sync on the '
      'phone too, then run the check here or there.';
}
