// Reliable blob layer pieces of the sync engine (T4): content-addressed blobs
// split into chunks, reassembled and SHA-256 verified on the receiving side.
import 'dart:typed_data';

import 'package:chameleonultragui/sync/sync_records.dart';

/// Purposes of blobs inside one sync session.
class BlobPurpose {
  static const manifest = 'manifest';
  static const cards = 'cards';
  static const dictionaries = 'dictionaries';
}

/// Blob offered by this side.
class OutBlob {
  final String id;
  final String purpose;
  final Uint8List bytes;
  final String sha256;
  final int chunkSize;

  /// The peer asked for data (or acknowledged): stop re-offering.
  bool confirmed = false;
  bool acked = false;
  bool pumping = false;
  final Set<int> wanted = {};
  final Set<int> sentOnce = {};

  OutBlob(this.purpose, this.bytes, this.chunkSize)
    : sha256 = sha256Hex(bytes),
      id = '$purpose:${sha256Hex(bytes)}';

  int get chunkCount => bytes.isEmpty ? 0 : (bytes.length + chunkSize - 1) ~/ chunkSize;

  Uint8List chunk(int index) {
    final start = index * chunkSize;
    final end = start + chunkSize > bytes.length ? bytes.length : start + chunkSize;
    return Uint8List.sublistView(bytes, start, end);
  }

  int chunkLength(int index) => chunk(index).length;
}

/// Blob being received (possibly resumed from an earlier session).
class InBlob {
  final String id;
  final String purpose;
  final int totalBytes;
  final int chunkSize;
  final String sha256;
  final Map<int, Uint8List> chunks = {};
  Uint8List? data;
  bool verified = false;
  int integrityFailures = 0;
  int activeBulks = 0;
  DateTime lastActivity = DateTime.now();

  InBlob({
    required this.id,
    required this.purpose,
    required this.totalBytes,
    required this.chunkSize,
    required this.sha256,
  });

  int get chunkCount => totalBytes == 0 ? 0 : (totalBytes + chunkSize - 1) ~/ chunkSize;

  int expectedLength(int index) {
    if (index < 0 || index >= chunkCount) return -1;
    final start = index * chunkSize;
    final end = start + chunkSize > totalBytes ? totalBytes : start + chunkSize;
    return end - start;
  }

  int get receivedBytes => verified
      ? totalBytes
      : chunks.values.fold(0, (a, c) => a + c.length);

  List<int> missing() => [
    for (var i = 0; i < chunkCount; i++)
      if (!chunks.containsKey(i)) i,
  ];

  /// Concatenates all chunks. Call only when [missing] is empty.
  Uint8List assemble() {
    final out = Uint8List(totalBytes);
    for (var i = 0; i < chunkCount; i++) {
      out.setRange(i * chunkSize, i * chunkSize + chunks[i]!.length, chunks[i]!);
    }
    return out;
  }

  /// Verified payload for [BlobPurpose]-independent reuse, null until then.
  bool matches(int totalBytes, int chunkSize, String sha256) =>
      this.totalBytes == totalBytes &&
      this.chunkSize == chunkSize &&
      this.sha256 == sha256;
}

/// Compresses sorted indices into `[start, endExclusive]` ranges for messages.
List<List<int>> toRanges(List<int> indices) {
  final out = <List<int>>[];
  for (final i in indices) {
    if (out.isNotEmpty && out.last[1] == i) {
      out.last[1] = i + 1;
    } else {
      out.add([i, i + 1]);
    }
  }
  return out;
}

/// Inverse of [toRanges], bounded by [limit] to refuse absurd input.
List<int> fromRanges(Object? raw, int limit) {
  final out = <int>[];
  for (final r in raw as List<dynamic>) {
    final s = (r as List<dynamic>)[0] as int;
    final e = r[1] as int;
    for (var i = s; i < e && i < limit; i++) {
      if (i >= 0) out.add(i);
    }
  }
  return out;
}

/// Receiver-side store of blobs that survive a failed session, so that a
/// retry only fetches what is still missing. Content-addressed, so a stale
/// entry can never be wrong, only unused.
class SyncResumeCache {
  final int maxEntries;
  final Map<String, InBlob> _blobs = {};

  SyncResumeCache({this.maxEntries = 8});

  InBlob? take(String id) => _blobs.remove(id);

  void put(InBlob blob) {
    _blobs.remove(blob.id);
    _blobs[blob.id] = blob;
    while (_blobs.length > maxEntries) {
      _blobs.remove(_blobs.keys.first);
    }
  }

  int get length => _blobs.length;

  /// Number of chunks cached for [id] (verified blobs count as complete).
  int cachedChunks(String id) => _blobs[id]?.chunks.length ?? 0;

  void clear() => _blobs.clear();
}
