import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';

/// What to do with a chunk (or message) in flight.
class ChunkFate {
  /// Deliver this many copies (0 = drop, 2 = duplicate).
  final int copies;

  /// Hold the chunk back until [InMemorySyncTransport.flushHeld] is called
  /// (use to reorder: hold chunk 1, let 2 and 3 through, then flush).
  final bool hold;

  const ChunkFate({this.copies = 1, this.hold = false});

  static const deliver = ChunkFate();
  static const drop = ChunkFate(copies: 0);
  static const duplicate = ChunkFate(copies: 2);
  static const held = ChunkFate(hold: true);
}

/// Decides the fate of a bulk chunk on the wire.
typedef ChunkHook = ChunkFate Function(BulkChunk chunk);

/// One end of an in-memory phone<->watch link. Create with
/// [InMemorySyncTransport.pair].
///
/// Behaviour:
///  * Messages are JSON-encoded and size-checked against [maxMessageBytes];
///    delivery is asynchronous (microtask), in order.
///  * Bulk chunks pass through [chunkHook] on the SENDING side so tests can
///    drop, duplicate or hold (reorder) chunks. Byte counters count each
///    delivered chunk's payload once per distinct index.
///  * [setPeerAvailable] flips availability on both ends; while unavailable,
///    sends throw [SyncTransportException].
class InMemorySyncTransport implements SyncTransport {
  @override
  final int maxMessageBytes;
  @override
  final int preferredChunkSize;

  /// Test hook: fate of every outgoing bulk chunk. Default delivers.
  ChunkHook? chunkHook;

  /// Test hook: fate of every outgoing message (only `copies` is honoured).
  ChunkFate Function(SyncMessage message)? messageHook;

  late InMemorySyncTransport _other;
  PeerState _state = PeerState.available;
  bool _disposed = false;

  final _stateCtl = StreamController<PeerState>.broadcast();
  final _messages = StreamController<SyncMessage>.broadcast();
  final _incoming = StreamController<IncomingBulk>.broadcast();
  final Map<String, _Incoming> _incomingById = {};
  final List<void Function()> _held = [];

  /// Every message this end sent (before the hook), for assertions.
  final List<SyncMessage> sentMessages = [];

  InMemorySyncTransport._(this.maxMessageBytes, this.preferredChunkSize);

  /// Returns a connected `(phone, watch)` pair.
  static (InMemorySyncTransport, InMemorySyncTransport) pair({
    int maxMessageBytes = 100 * 1024,
    int chunkSize = 16 * 1024,
  }) {
    final a = InMemorySyncTransport._(maxMessageBytes, chunkSize);
    final b = InMemorySyncTransport._(maxMessageBytes, chunkSize);
    a._other = b;
    b._other = a;
    return (a, b);
  }

  /// Sets link availability for both ends.
  void setPeerAvailable(bool available) {
    final s = available ? PeerState.available : PeerState.unavailable;
    for (final t in [this, _other]) {
      if (t._state == s) continue;
      t._state = s;
      t._stateCtl.add(s);
    }
    if (!available) {
      for (final t in [this, _other]) {
        for (final inc in t._incomingById.values) {
          inc.abort(BulkAbortReason.linkLost);
        }
      }
    }
  }

  /// Delivers every chunk held by [ChunkFate.held], in the order held.
  void flushHeld() {
    final held = List.of(_held);
    _held.clear();
    for (final f in held) {
      f();
    }
  }

  void _requireUp() {
    if (_disposed) throw StateError('transport disposed');
    if (_state != PeerState.available) {
      throw const SyncTransportException('peer unavailable');
    }
  }

  @override
  PeerState get currentPeerState => _state;

  @override
  Stream<PeerState> get peerState async* {
    yield _state;
    yield* _stateCtl.stream;
  }

  @override
  Future<SyncPeer?> getPeer() async => _state == PeerState.available
      ? const SyncPeer(id: 'in-memory-peer', displayName: 'Peer')
      : null;

  @override
  Future<void> sendMessage(SyncMessage message) async {
    _requireUp();
    final encoded = jsonEncode(message.toMap());
    if (utf8.encode(encoded).length > maxMessageBytes) {
      throw const SyncTransportException('message too large');
    }
    sentMessages.add(message);
    final fate = messageHook?.call(message) ?? ChunkFate.deliver;
    for (var i = 0; i < fate.copies; i++) {
      final copy = SyncMessage.fromMap(jsonDecode(encoded));
      scheduleMicrotask(() {
        if (!_other._messages.isClosed) _other._messages.add(copy);
      });
    }
  }

  @override
  Stream<SyncMessage> get messages => _messages.stream;

  @override
  Future<BulkSender> openBulk(BulkHeader header) async {
    _requireUp();
    final receiver = _Incoming(header);
    _other._incomingById[header.transferId] = receiver;
    scheduleMicrotask(() => _other._incoming.add(receiver));
    return _Sender(this, header, receiver);
  }

  @override
  Stream<IncomingBulk> get incomingBulk => _incoming.stream;

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _stateCtl.close();
    await _messages.close();
    await _incoming.close();
  }
}

class _Sender implements BulkSender {
  final InMemorySyncTransport _t;
  final _Incoming _rx;
  @override
  final BulkHeader header;
  final _progress = StreamController<BulkProgress>.broadcast();
  final Set<int> _sent = {};
  int _bytes = 0;
  bool _done = false;

  _Sender(this._t, this.header, this._rx) {
    _rx.abortedFuture.then((_) {
      _done = true;
    });
  }

  @override
  Stream<BulkProgress> get progress => _progress.stream;

  @override
  Future<void> sendChunk(int index, Uint8List bytes) async {
    if (_done) throw StateError('bulk transfer finished or cancelled');
    _t._requireUp();
    final chunk = BulkChunk(
      header.transferId,
      index,
      Uint8List.fromList(bytes),
    );
    if (_sent.add(index)) _bytes += bytes.length;
    _progress.add(BulkProgress(header.transferId, _bytes, header.totalBytes));
    final fate = _t.chunkHook?.call(chunk) ?? ChunkFate.deliver;
    void deliver() {
      for (var i = 0; i < fate.copies; i++) {
        _rx.add(chunk);
      }
    }

    if (fate.hold) {
      _t._held.add(deliver);
    } else {
      deliver();
    }
    // Yield so receivers interleave with senders, like a real link.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> end() async {
    if (_done) return;
    _done = true;
    _rx.close();
  }

  @override
  Future<void> cancel() async {
    if (_done) return;
    _done = true;
    _rx.abort(BulkAbortReason.cancelledByPeer);
  }
}

class _Incoming implements IncomingBulk {
  @override
  final BulkHeader header;
  final _chunks = StreamController<BulkChunk>();
  final _progress = StreamController<BulkProgress>.broadcast();
  final _aborted = Completer<BulkAbortReason>();
  final Set<int> _seen = {};
  int _bytes = 0;
  bool _closed = false;

  _Incoming(this.header);

  Future<BulkAbortReason> get abortedFuture => _aborted.future;

  void add(BulkChunk c) {
    if (_closed) return;
    if (_seen.add(c.index)) _bytes += c.bytes.length;
    _progress.add(BulkProgress(header.transferId, _bytes, header.totalBytes));
    _chunks.add(c);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _chunks.close();
  }

  void abort(BulkAbortReason reason) {
    if (!_aborted.isCompleted) _aborted.complete(reason);
    close();
  }

  @override
  Stream<BulkChunk> get chunks => _chunks.stream;

  @override
  Stream<BulkProgress> get progress => _progress.stream;

  @override
  Future<BulkAbortReason> get aborted => _aborted.future;

  @override
  Future<void> cancel() async => abort(BulkAbortReason.cancelledByLocal);
}
