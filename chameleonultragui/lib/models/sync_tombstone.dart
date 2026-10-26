import 'dart:convert';

/// Kind of synced entity a [SyncTombstone] refers to.
enum SyncEntityKind {
  card,
  cardFolder,
  dictionary,
  dictionaryFolder;

  static SyncEntityKind fromName(String name) =>
      SyncEntityKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => throw FormatException('Unknown sync entity kind: $name'),
      );
}

/// Record of a deletion, kept so that a delete can be propagated by sync.
///
/// A tombstone beats an entity with the same [kind]/[id] when
/// `deletedAt > entity.updatedAt` (see plan section 4, T4).
class SyncTombstone {
  final String id;
  final SyncEntityKind kind;

  /// Deletion time, epoch milliseconds.
  final int deletedAt;

  const SyncTombstone({
    required this.id,
    required this.kind,
    required this.deletedAt,
  });

  factory SyncTombstone.fromJson(String source) =>
      SyncTombstone.fromMap(jsonDecode(source) as Map<String, dynamic>);

  factory SyncTombstone.fromMap(Map<String, dynamic> data) => SyncTombstone(
    id: data['id'] as String,
    kind: SyncEntityKind.fromName(data['kind'] as String),
    deletedAt: data['deletedAt'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind.name,
    'deletedAt': deletedAt,
  };

  String toJson() => jsonEncode(toMap());

  @override
  bool operator ==(Object other) =>
      other is SyncTombstone &&
      other.id == id &&
      other.kind == kind &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, kind, deletedAt);

  @override
  String toString() => 'SyncTombstone($kind $id @ $deletedAt)';
}
