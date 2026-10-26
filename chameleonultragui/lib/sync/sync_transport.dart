// FROZEN CONTRACT (Track 0B). Changes require a PR labelled `contract-change`.
//
// Transport abstraction between phone and watch. Pure Dart; the sync engine
// (T4) depends only on this. Implementations:
//  * T5: Wear Data Layer implementation backed by the `wear_sync` plugin
//    (MessageClient for messages, ChannelClient for bulk).
//  * 0B: `InMemorySyncTransport` in test/fakes for host tests.
//
// RELIABILITY MODEL. Small messages are best-effort (an implementation may
// lose, duplicate or reorder them; the engine retries by request id). Bulk
// chunks carry an index; the transport MAY deliver them out of order, twice
// or not at all, and the engine (T4) owns reassembly, SHA-256 verification
// and resume by chunk index. A transport that is already reliable simply
// never exercises those paths.
import 'dart:typed_data';

import 'package:chameleonultragui/sync/sync_models.dart';

/// Link state to the paired device.
enum PeerState {
  /// No paired device reachable.
  unavailable,

  /// Paired device reachable (nearby / connected).
  available,
}

/// The remote device, as the transport sees it.
class SyncPeer {
  /// Transport-level node id (opaque).
  final String id;
  final String displayName;

  const SyncPeer({required this.id, this.displayName = ''});
}

/// Byte-level progress of one bulk transfer, in either direction.
class BulkProgress {
  final String transferId;

  /// Bytes handed to / received from the link so far (counts each chunk's
  /// payload once even if redelivered).
  final int bytesTransferred;
  final int totalBytes;

  const BulkProgress(this.transferId, this.bytesTransferred, this.totalBytes);

  double get fraction => totalBytes == 0 ? 1 : bytesTransferred / totalBytes;
}

/// One bulk chunk.
class BulkChunk {
  final String transferId;

  /// 0-based; `bytes` covers `[index * chunkSize, index * chunkSize + len)`.
  final int index;
  final Uint8List bytes;

  const BulkChunk(this.transferId, this.index, this.bytes);
}

/// Why a bulk transfer ended without completing.
enum BulkAbortReason { cancelledByLocal, cancelledByPeer, linkLost, error }

/// Sending half of a bulk transfer.
abstract class BulkSender {
  BulkHeader get header;

  /// Sends chunk [index]. Completes when the chunk was handed to the link
  /// (applies backpressure). Throws [StateError] after cancel/end and
  /// [SyncTransportException] on link failure. Callers may send chunks in any
  /// order and re-send (resume).
  Future<void> sendChunk(int index, Uint8List bytes);

  /// Byte-level progress (emits after each `sendChunk`). Broadcast.
  Stream<BulkProgress> get progress;

  /// Signals "all chunks sent". Does not guarantee receipt; confirm via an
  /// engine-level ack message.
  Future<void> end();

  /// Aborts; the receiver's [IncomingBulk.aborted] completes with
  /// `cancelledByPeer`.
  Future<void> cancel();
}

/// Receiving half of a bulk transfer.
abstract class IncomingBulk {
  BulkHeader get header;

  /// Chunks as delivered (see reliability model). Closes after the sender's
  /// `end()` once buffered chunks are delivered, or on abort.
  Stream<BulkChunk> get chunks;

  /// Byte-level receive progress. Broadcast.
  Stream<BulkProgress> get progress;

  /// Completes if the transfer is aborted; never completes on success.
  Future<BulkAbortReason> get aborted;

  /// Aborts from the receiving side.
  Future<void> cancel();
}

/// Error from the transport layer.
class SyncTransportException implements Exception {
  final String message;

  const SyncTransportException(this.message);

  @override
  String toString() => 'SyncTransportException: $message';
}

abstract class SyncTransport {
  /// Max encoded size of a single [sendMessage] payload in bytes (Wear
  /// MessageClient is limited to roughly 100 KB). Larger data must use bulk.
  int get maxMessageBytes;

  /// Recommended chunk size for [openBulk].
  int get preferredChunkSize;

  /// Current link state; emits the current value on listen, then changes.
  Stream<PeerState> get peerState;

  /// Synchronous view of the latest [peerState].
  PeerState get currentPeerState;

  /// The paired device if [currentPeerState] is available, else null.
  Future<SyncPeer?> getPeer();

  /// Sends a small control message. Throws [SyncTransportException] if no
  /// peer is available or the encoded size exceeds [maxMessageBytes].
  Future<void> sendMessage(SyncMessage message);

  /// Incoming control messages. Broadcast.
  Stream<SyncMessage> get messages;

  /// Starts an outgoing bulk transfer; the peer is notified via its
  /// [incomingBulk] stream.
  Future<BulkSender> openBulk(BulkHeader header);

  /// Incoming bulk transfers. Broadcast.
  Stream<IncomingBulk> get incomingBulk;

  /// Releases resources; further use throws [StateError].
  Future<void> dispose();
}
