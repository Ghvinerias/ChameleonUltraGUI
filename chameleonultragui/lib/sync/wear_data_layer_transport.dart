import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:wear_sync/wear_sync.dart';

/// [SyncTransport] over the Wear OS Data Layer (`wear_sync` plugin).
///
/// Messages use MessageClient; bulk transfers use one ChannelClient stream per
/// transfer. The link is a reliable stream, so chunks arrive in order and
/// exactly once while the channel lives; a broken channel aborts the transfer.
///
/// Without Google Play Services [create] still succeeds and the transport
/// stays `PeerState.unavailable` forever ([isSupported] is false).
class WearDataLayerTransport implements SyncTransport {
  final WearSyncPlatform _platform;
  final WearSyncStatus _status;

  @override
  final int preferredChunkSize;

  PeerState _state = PeerState.unavailable;
  WearPeerInfo? _peer;
  bool _disposed = false;
  StreamSubscription<WearSyncEvent>? _sub;

  final _stateCtl = StreamController<PeerState>.broadcast();
  final _messages = StreamController<SyncMessage>.broadcast();
  final _incoming = StreamController<IncomingBulk>.broadcast();
  final Map<String, _WearIncoming> _incomingById = {};
  final Map<String, _WearSender> _sendersById = {};

  WearDataLayerTransport._(
    this._platform,
    this._status,
    this.preferredChunkSize,
  );

  /// Connects to the plugin and starts listening. Never throws because of a
  /// missing Play Services; check [isSupported].
  static Future<WearDataLayerTransport> create({
    WearSyncPlatform? platform,
    int preferredChunkSize = 32 * 1024,
  }) async {
    final p = platform ?? MethodChannelWearSync();
    final status = await p.getStatus();
    final t = WearDataLayerTransport._(p, status, preferredChunkSize);
    if (status.available) {
      // Native emits the current peer on first listen.
      t._sub = p.events.listen(t._onEvent, onError: (_) {});
    }
    return t;
  }

  /// False when Google Play Services / the Wearable API is unavailable.
  bool get isSupported => _status.available;

  /// Why sync is unavailable, if it is.
  String? get unsupportedReason => _status.reason;

  @override
  int get maxMessageBytes => _status.maxMessageBytes;

  @override
  PeerState get currentPeerState => _state;

  @override
  Stream<PeerState> get peerState {
    late StreamController<PeerState> c;
    StreamSubscription<PeerState>? sub;
    c = StreamController<PeerState>(
      onListen: () {
        c.add(_state);
        sub = _stateCtl.stream.listen(c.add, onDone: c.close);
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<SyncPeer?> getPeer() async {
    _checkAlive();
    if (!_status.available) return null;
    final p = _state == PeerState.available ? _peer : null;
    return p == null ? null : SyncPeer(id: p.id, displayName: p.name);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('transport disposed');
  }

  void _requireUp() {
    _checkAlive();
    if (!_status.available) {
      throw SyncTransportException(
        'sync unavailable: ${_status.reason ?? 'no Google Play Services'}',
      );
    }
    if (_state != PeerState.available) {
      throw const SyncTransportException('peer unavailable');
    }
  }

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on WearSyncException catch (e) {
      throw SyncTransportException('${e.code}: ${e.message ?? ''}');
    }
  }

  void _onEvent(WearSyncEvent e) {
    if (_disposed) return;
    switch (e) {
      case WearPeerEvent():
        _peer = e.peer;
        final s = e.peer == null ? PeerState.unavailable : PeerState.available;
        if (s != _state) {
          _state = s;
          _stateCtl.add(s);
        }
      case WearMessageEvent():
        try {
          final map = jsonDecode(utf8.decode(e.bytes));
          _messages.add(SyncMessage.fromMap(Map<String, dynamic>.from(map)));
        } catch (_) {
          // Malformed message: drop (best-effort channel).
        }
      case WearIncomingBulkEvent():
        try {
          final header = BulkHeader.fromMap(
            Map<String, dynamic>.from(jsonDecode(utf8.decode(e.header))),
          );
          final inc = _WearIncoming(this, header);
          _incomingById[e.transferId] = inc;
          _incoming.add(inc);
        } catch (_) {
          _platform.cancelBulk(e.transferId).catchError((_) {});
        }
      case WearChunkEvent():
        _incomingById[e.transferId]?.add(
          BulkChunk(e.transferId, e.index, e.bytes),
        );
      case WearBulkEndEvent():
        _incomingById.remove(e.transferId)?.close();
        _sendersById.remove(e.transferId)?._done = true;
      case WearBulkAbortedEvent():
        final reason = switch (e.reason) {
          'cancelledByPeer' => BulkAbortReason.cancelledByPeer,
          'linkLost' => BulkAbortReason.linkLost,
          _ => BulkAbortReason.error,
        };
        _incomingById.remove(e.transferId)?.abort(reason);
        _sendersById.remove(e.transferId)?._done = true;
    }
  }

  @override
  Future<void> sendMessage(SyncMessage message) async {
    _requireUp();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message.toMap())));
    if (bytes.length > maxMessageBytes) {
      throw const SyncTransportException('message too large');
    }
    await _guard(() => _platform.sendMessage(bytes));
  }

  @override
  Stream<SyncMessage> get messages => _messages.stream;

  @override
  Future<BulkSender> openBulk(BulkHeader header) async {
    _requireUp();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(header.toMap())));
    await _guard(() => _platform.openBulk(header.transferId, bytes));
    final s = _WearSender(this, header);
    _sendersById[header.transferId] = s;
    return s;
  }

  @override
  Stream<IncomingBulk> get incomingBulk => _incoming.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final i in _incomingById.values.toList()) {
      i.abort(BulkAbortReason.error);
    }
    _incomingById.clear();
    for (final s in _sendersById.values) {
      s._done = true;
    }
    _sendersById.clear();
    await _sub?.cancel(); // native removes listeners and closes channels
    await _stateCtl.close();
    await _messages.close();
    await _incoming.close();
  }
}

class _WearSender implements BulkSender {
  final WearDataLayerTransport _t;
  @override
  final BulkHeader header;
  final _progress = StreamController<BulkProgress>.broadcast();
  final Set<int> _sent = {};
  int _bytes = 0;
  bool _done = false;

  _WearSender(this._t, this.header);

  @override
  Stream<BulkProgress> get progress => _progress.stream;

  @override
  Future<void> sendChunk(int index, Uint8List bytes) async {
    if (_done) throw StateError('bulk transfer finished or cancelled');
    try {
      await _t._guard(
        () => _t._platform.sendChunk(header.transferId, index, bytes),
      );
    } on SyncTransportException {
      if (_done) throw StateError('bulk transfer finished or cancelled');
      rethrow;
    }
    if (_sent.add(index)) _bytes += bytes.length;
    if (!_progress.isClosed) {
      _progress.add(BulkProgress(header.transferId, _bytes, header.totalBytes));
    }
  }

  @override
  Future<void> end() async {
    if (_done) return;
    await _t._guard(() => _t._platform.endBulk(header.transferId));
    _done = true;
    _t._sendersById.remove(header.transferId);
    await _progress.close();
  }

  @override
  Future<void> cancel() async {
    if (_done) return;
    _done = true;
    _t._sendersById.remove(header.transferId);
    try {
      await _t._guard(() => _t._platform.cancelBulk(header.transferId));
    } finally {
      await _progress.close();
    }
  }
}

class _WearIncoming implements IncomingBulk {
  final WearDataLayerTransport _t;
  @override
  final BulkHeader header;
  final _chunks = StreamController<BulkChunk>();
  final _progress = StreamController<BulkProgress>.broadcast();
  final _aborted = Completer<BulkAbortReason>();
  final Set<int> _seen = {};
  int _bytes = 0;
  bool _closed = false;

  _WearIncoming(this._t, this.header);

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
    _progress.close();
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
  Future<void> cancel() async {
    if (_closed) return;
    _t._incomingById.remove(header.transferId);
    abort(BulkAbortReason.cancelledByLocal);
    try {
      await _t._platform.cancelBulk(header.transferId);
    } catch (_) {}
  }
}
