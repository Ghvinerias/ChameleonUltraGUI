/// Rough duration of a Mifare Classic key check.
///
/// Each BLE chunk carries up to [kKeyChunkSize] keys and costs about
/// [kChunkMillis] ms per sector (measured order of magnitude on the phone
/// path, not on the watch: treat as an estimate). A 1K card has
/// [kDefaultSectors] sectors.
///
/// seconds = ceil(keys / 32) * 0.07 * sectors
const kKeyChunkSize = 32;
const kChunkMillis = 70;
const kDefaultSectors = 16;

/// Above this the UI warns that a check will take long.
const kLargeCheckThreshold = Duration(seconds: 90);

Duration estimateKeyCheck(int keyCount, {int sectors = kDefaultSectors}) {
  if (keyCount <= 0) return Duration.zero;
  final chunks = (keyCount + kKeyChunkSize - 1) ~/ kKeyChunkSize;
  return Duration(milliseconds: chunks * kChunkMillis * sectors);
}

/// "45 s" / "3 min".
String formatEstimate(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  if (s < 90) return '$s s';
  return '${(s / 60).round()} min';
}
