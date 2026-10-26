// FROZEN CONTRACT (Track 0B). Changes require a PR labelled `contract-change`.
//
// Wire data classes shared by the sync engine (T4) and transports (T5).
// All have `toJson`/`fromJson` over plain JSON maps; the engine encodes
// them with `jsonEncode` + UTF-8 for small messages.
import 'package:chameleonultragui/models/sync_tombstone.dart';

/// Current sync protocol version. Bump on any incompatible change to the
/// messages in this file or to the bulk framing; peers compare versions in the
/// [SyncHandshake].
const int kSyncProtocolVersion = 1;

/// Oldest protocol version this build can still talk to.
const int kSyncMinProtocolVersion = 1;

/// Which side of the pair a device is. On ties (equal timestamps) the phone
/// wins.
enum SyncRole { phone, watch }

/// One synced entity as seen by the manifest.
class SyncManifestEntry {
  final SyncEntityKind kind;
  final String id;

  /// Epoch ms; entities without a stamp (legacy) are reported as 0.
  final int updatedAt;

  /// Lower-case hex SHA-256 of the entity's canonical JSON (`toJson()` output).
  final String hash;

  /// Size in bytes of that JSON (UTF-8).
  final int size;

  const SyncManifestEntry({
    required this.kind,
    required this.id,
    required this.updatedAt,
    required this.hash,
    required this.size,
  });

  factory SyncManifestEntry.fromMap(Map<String, dynamic> m) =>
      SyncManifestEntry(
        kind: SyncEntityKind.fromName(m['kind'] as String),
        id: m['id'] as String,
        updatedAt: m['updatedAt'] as int,
        hash: m['hash'] as String,
        size: m['size'] as int,
      );

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'id': id,
    'updatedAt': updatedAt,
    'hash': hash,
    'size': size,
  };

  @override
  bool operator ==(Object other) =>
      other is SyncManifestEntry &&
      other.kind == kind &&
      other.id == id &&
      other.updatedAt == updatedAt &&
      other.hash == hash &&
      other.size == size;

  @override
  int get hashCode => Object.hash(kind, id, updatedAt, hash, size);
}

/// Full inventory of a replica: live entities plus tombstones.
class SyncManifest {
  final List<SyncManifestEntry> entries;
  final List<SyncTombstone> tombstones;

  const SyncManifest({this.entries = const [], this.tombstones = const []});

  factory SyncManifest.fromMap(Map<String, dynamic> m) => SyncManifest(
    entries: (m['entries'] as List<dynamic>)
        .map((e) => SyncManifestEntry.fromMap(e as Map<String, dynamic>))
        .toList(),
    tombstones: (m['tombstones'] as List<dynamic>)
        .map((e) => SyncTombstone.fromMap(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toMap() => {
    'entries': entries.map((e) => e.toMap()).toList(),
    'tombstones': tombstones.map((t) => t.toMap()).toList(),
  };
}

/// First message each side sends after the transport reports a peer.
class SyncHandshake {
  final int protocolVersion;
  final int minProtocolVersion;
  final SyncRole role;

  /// Stable per-install id.
  final String deviceId;

  /// Human-readable app version, informational.
  final String appVersion;

  /// Feature flags, e.g. `dictionaryMirror`.
  final List<String> capabilities;

  const SyncHandshake({
    this.protocolVersion = kSyncProtocolVersion,
    this.minProtocolVersion = kSyncMinProtocolVersion,
    required this.role,
    required this.deviceId,
    this.appVersion = '',
    this.capabilities = const [],
  });

  /// Whether both sides can speak a common version.
  bool isCompatibleWith(SyncHandshake other) =>
      protocolVersion >= other.minProtocolVersion &&
      other.protocolVersion >= minProtocolVersion;

  factory SyncHandshake.fromMap(Map<String, dynamic> m) => SyncHandshake(
    protocolVersion: m['protocolVersion'] as int,
    minProtocolVersion: m['minProtocolVersion'] as int,
    role: SyncRole.values.byName(m['role'] as String),
    deviceId: m['deviceId'] as String,
    appVersion: (m['appVersion'] ?? '') as String,
    capabilities: List<String>.from(m['capabilities'] as List<dynamic>),
  );

  Map<String, dynamic> toMap() => {
    'protocolVersion': protocolVersion,
    'minProtocolVersion': minProtocolVersion,
    'role': role.name,
    'deviceId': deviceId,
    'appVersion': appVersion,
    'capabilities': capabilities,
  };
}

/// Envelope of a small control message.
///
/// `type` values are owned by T4 (e.g. `handshake`, `manifest`, `request`,
/// `ack`, `resume`); the transport treats them opaquely.
class SyncMessage {
  final String type;

  /// Correlates request/response pairs. Optional.
  final String? id;

  /// JSON-encodable payload.
  final Map<String, dynamic> payload;

  const SyncMessage({required this.type, this.id, this.payload = const {}});

  factory SyncMessage.fromMap(Map<String, dynamic> m) => SyncMessage(
    type: m['type'] as String,
    id: m['id'] as String?,
    payload: Map<String, dynamic>.from(
      (m['payload'] ?? const <String, dynamic>{}) as Map,
    ),
  );

  Map<String, dynamic> toMap() => {
    'type': type,
    if (id != null) 'id': id,
    'payload': payload,
  };
}

/// Header describing a bulk transfer (announced before the first chunk).
class BulkHeader {
  /// Unique per transfer; chosen by the sender.
  final String transferId;

  /// Total payload size in bytes.
  final int totalBytes;

  /// Size of every chunk except possibly the last.
  final int chunkSize;

  /// Free-form string metadata (e.g. `kind`, `sha256`), owned by T4.
  final Map<String, String> metadata;

  const BulkHeader({
    required this.transferId,
    required this.totalBytes,
    required this.chunkSize,
    this.metadata = const {},
  });

  int get chunkCount =>
      totalBytes == 0 ? 0 : (totalBytes + chunkSize - 1) ~/ chunkSize;

  factory BulkHeader.fromMap(Map<String, dynamic> m) => BulkHeader(
    transferId: m['transferId'] as String,
    totalBytes: m['totalBytes'] as int,
    chunkSize: m['chunkSize'] as int,
    metadata: Map<String, String>.from(
      (m['metadata'] ?? const <String, String>{}) as Map,
    ),
  );

  Map<String, dynamic> toMap() => {
    'transferId': transferId,
    'totalBytes': totalBytes,
    'chunkSize': chunkSize,
    'metadata': metadata,
  };
}
