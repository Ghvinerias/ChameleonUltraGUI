// Result of a sync run (T4). Plain data, no localized strings.
import 'package:chameleonultragui/models/sync_tombstone.dart';

class SyncCounts {
  final int added;
  final int updated;
  final int deleted;

  const SyncCounts({this.added = 0, this.updated = 0, this.deleted = 0});

  bool get isEmpty => added == 0 && updated == 0 && deleted == 0;

  SyncCounts copyWith({int? added, int? updated, int? deleted}) => SyncCounts(
    added: added ?? this.added,
    updated: updated ?? this.updated,
    deleted: deleted ?? this.deleted,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncCounts &&
      other.added == added &&
      other.updated == updated &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(added, updated, deleted);

  @override
  String toString() => '+$added ~$updated -$deleted';
}

/// What changed on one device, per entity kind.
class SyncSideReport {
  final Map<SyncEntityKind, SyncCounts> byKind;

  const SyncSideReport(this.byKind);

  SyncCounts of(SyncEntityKind kind) => byKind[kind] ?? const SyncCounts();

  bool get isEmpty => byKind.values.every((c) => c.isEmpty);

  int get totalAdded => byKind.values.fold(0, (a, c) => a + c.added);
  int get totalUpdated => byKind.values.fold(0, (a, c) => a + c.updated);
  int get totalDeleted => byKind.values.fold(0, (a, c) => a + c.deleted);

  @override
  String toString() => byKind.entries
      .where((e) => !e.value.isEmpty)
      .map((e) => '${e.key.name}: ${e.value}')
      .join(', ');
}

class SyncReport {
  final String sessionId;

  /// Changes applied on the phone / on the watch.
  final SyncSideReport phone;
  final SyncSideReport watch;

  /// Equal-stamp ties and mirror overrides (see the merge rules). A plain
  /// one-sided update is not counted: without a stored common base it cannot
  /// be told apart from a conflict.
  final int conflictsResolved;

  /// Entities moved to the root because their folder was deleted or a folder
  /// cycle had to be broken (same on both replicas).
  final int orphansMovedToRoot;

  /// Payload bytes this device put on / took from the link (retransmitted
  /// chunks count again on the send side).
  final int bytesSent;
  final int bytesReceived;
  final Duration duration;

  const SyncReport({
    required this.sessionId,
    required this.phone,
    required this.watch,
    required this.conflictsResolved,
    required this.orphansMovedToRoot,
    required this.bytesSent,
    required this.bytesReceived,
    required this.duration,
  });

  /// True when the sync changed nothing on either device.
  bool get isNoOp => phone.isEmpty && watch.isEmpty && orphansMovedToRoot == 0;

  @override
  String toString() =>
      'SyncReport(phone: [$phone], watch: [$watch], conflicts: '
      '$conflictsResolved, orphans: $orphansMovedToRoot, '
      'sent: $bytesSent, received: $bytesReceived)';
}
