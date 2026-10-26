// FROZEN CONTRACT (Track 0B).
import 'package:chameleonultragui/models/sync_tombstone.dart';

enum StoreChangeType { created, updated, deleted }

/// Who caused a change. Sync-applied changes must not be re-uploaded as new
/// local edits.
enum StoreChangeOrigin { local, sync }

/// One mutation of a store, emitted on its `changes` stream after it has been
/// persisted.
class StoreChange {
  final SyncEntityKind kind;
  final String id;
  final StoreChangeType type;
  final StoreChangeOrigin origin;

  const StoreChange({
    required this.kind,
    required this.id,
    required this.type,
    this.origin = StoreChangeOrigin.local,
  });

  @override
  String toString() => 'StoreChange($kind $id $type $origin)';
}
