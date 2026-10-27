// One sync run (T4). Internal: use `SyncEngine`.
//
// Message flow (phone initiates; every step is idempotent and retried):
//   phone  sync.hello       ->  watch      (handshake, options, session id)
//   watch  sync.hello-ack   ->  phone
//   both   manifest blob    ->  peer       (offer / want / chunks / ack)
//   both   compute the same plan from the two manifests
//   both   bundle blobs     ->  peer       (only what the peer must take)
//   both   stage: reassemble, verify SHA-256, parse, check against manifest
//   watch  sync.ready       ->  phone      (staged, nothing applied yet)
//   phone  sync.commit      ->  watch      (phone staged too)
//   watch  applies, sync.done -> phone     (then the phone applies)
// Nothing touches a store before the commit step.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/models/sync_extensions.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_blob.dart';
import 'package:chameleonultragui/sync/sync_errors.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_normalize.dart';
import 'package:chameleonultragui/sync/sync_records.dart';
import 'package:chameleonultragui/sync/sync_report.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:chameleonultragui/sync/sync_types.dart';

class SyncMsg {
  static const hello = 'sync.hello';
  static const helloAck = 'sync.hello-ack';
  static const error = 'sync.error';
  static const offer = 'sync.offer';
  static const want = 'sync.want';
  static const ack = 'sync.ack';
  static const ready = 'sync.ready';
  static const commit = 'sync.commit';
  static const done = 'sync.done';
}

/// Sanity limit for a single blob, to refuse absurd offers.
const int kMaxBlobBytes = 64 * 1024 * 1024;

class SyncRun implements SyncSession {
  SyncRun({
    required this.id,
    required this.role,
    required this.transport,
    required this.cards,
    required this.dictionaries,
    required this.options,
    required this.handshake,
    required this.cache,
    required this.clock,
    required this.onEvent,
    required this.onFinished,
  }) {
    _result.future.ignore();
  }

  @override
  final String id;
  final SyncRole role;
  final SyncTransport transport;
  final CardStore cards;
  final DictionaryStore dictionaries;
  SyncOptions options;
  final SyncHandshake handshake;
  final SyncResumeCache cache;
  final int Function() clock;
  final void Function(SyncEvent) onEvent;
  final void Function(SyncRun, bool ok) onFinished;

  SyncRole get _peerRole =>
      role == SyncRole.phone ? SyncRole.watch : SyncRole.phone;

  final _events = StreamController<SyncEvent>.broadcast();
  final _result = Completer<SyncReport>();
  final _stopwatch = Stopwatch()..start();
  Timer? _timer;
  StreamSubscription<PeerState>? _peerSub;

  SyncPhase _phase = SyncPhase.connecting;
  bool _finished = false;
  bool _helloDone = false;
  bool _mirror = false;
  DateTime _lastRx = DateTime.now();
  final DateTime _started = DateTime.now();

  SyncSnapshot? _local;
  SyncManifest? _peerManifest;
  SyncPlan? _plan;
  bool _staged = false;
  bool _peerReady = false;
  bool _commitSent = false;
  bool _applying = false;
  bool _committed = false;

  final Map<String, OutBlob> _out = {};
  final Map<String, InBlob> _in = {};
  final Set<String> _expectedPurposes = {};
  final List<BulkSender> _senders = [];
  final List<IncomingBulk> _incoming = [];
  int _round = 0;
  int _bytesSent = 0;
  int _bytesReceived = 0;

  Map<SyncKey, String> _writes = {};
  Map<SyncKey, String> _finalNormalized = {};
  int _rewrites = 0;

  @override
  SyncPhase get phase => _phase;
  @override
  Stream<SyncEvent> get events => _events.stream;
  @override
  Future<SyncReport> get result => _result.future;
  bool get isFinished => _finished;

  // ---------------------------------------------------------------- lifecycle

  /// Phone: starts the handshake.
  void beginAsPhone() {
    if (transport.currentPeerState != PeerState.available) {
      _fail(
        const SyncException(
          SyncErrorCode.peerUnavailable,
          'no paired device reachable',
        ),
        notifyPeer: false,
      );
      return;
    }
    _mirror = options.mirrorDictionaries;
    _startTimers();
    _emitPhase(SyncPhase.connecting);
    _sendHello();
  }

  /// Watch: handles the first hello.
  void beginAsWatch(SyncMessage hello) {
    _startTimers();
    _emitPhase(SyncPhase.connecting);
    onMessage(hello);
  }

  void _startTimers() {
    _peerSub = transport.peerState.listen((s) {
      if (s == PeerState.unavailable && !_finished) {
        _fail(
          SyncException(
            _helloDone
                ? SyncErrorCode.transportLost
                : SyncErrorCode.peerUnavailable,
            'link lost',
          ),
          notifyPeer: false,
        );
      }
    });
    _timer = Timer.periodic(options.retryInterval, (_) => _tick());
  }

  void _tick() {
    if (_finished) return;
    final now = DateTime.now();
    if (!_helloDone) {
      if (role == SyncRole.phone &&
          now.difference(_started) > options.handshakeTimeout) {
        _fail(
          const SyncException(
            SyncErrorCode.peerUnavailable,
            'handshake not answered',
          ),
        );
        return;
      }
      if (role == SyncRole.phone) _sendHello();
    }
    if (now.difference(_lastRx) > options.idleTimeout) {
      _fail(
        const SyncException(SyncErrorCode.timeout, 'peer went silent'),
      );
      return;
    }
    if (!_helloDone) return;
    for (final b in _out.values) {
      if (!b.confirmed && !b.acked && !b.pumping) _sendOffer(b);
    }
    for (final b in _in.values) {
      if (b.verified || b.activeBulks > 0) continue;
      if (now.difference(b.lastActivity) >= options.retryInterval) {
        b.lastActivity = now;
        _sendWant(b);
      }
    }
    if (_staged && role == SyncRole.watch && !_committed && !_applying) {
      _send(SyncMsg.ready, {});
    }
    if (_commitSent && role == SyncRole.phone && !_applying) {
      _send(SyncMsg.commit, {});
    }
  }

  @override
  bool cancel() {
    if (_finished || _commitSent || _applying || _committed) return false;
    _fail(const SyncException(SyncErrorCode.cancelled, 'cancelled locally'));
    return true;
  }

  void _fail(SyncException e, {bool notifyPeer = true}) {
    if (_finished) return;
    _finished = true;
    if (notifyPeer) {
      _sendRaw(SyncMsg.error, {'code': e.code.name, 'message': e.message});
    }
    _teardown();
    final event = SyncFailedEvent(id, e);
    onEvent(event);
    if (!_events.isClosed) {
      _events.add(event);
      _events.close();
    }
    if (!_result.isCompleted) _result.completeError(e);
    onFinished(this, false);
  }

  void _succeed(SyncReport report) {
    if (_finished) return;
    _finished = true;
    _teardown();
    _phase = SyncPhase.done;
    final event = SyncDoneEvent(id, report);
    onEvent(event);
    if (!_events.isClosed) {
      _events.add(event);
      _events.close();
    }
    if (!_result.isCompleted) _result.complete(report);
    onFinished(this, true);
  }

  /// Aborts a run replaced by a newer session.
  void supersede() => _fail(
    const SyncException(SyncErrorCode.cancelled, 'superseded', fromPeer: true),
    notifyPeer: false,
  );

  void _teardown() {
    _timer?.cancel();
    _peerSub?.cancel();
    for (final s in _senders) {
      s.cancel().catchError((_) {});
    }
    _senders.clear();
    for (final i in _incoming) {
      i.cancel().catchError((_) {});
    }
    _incoming.clear();
    // Keep received blobs of a failed run so a retry can resume.
    if (!_committed) {
      for (final b in _in.values) {
        cache.put(b);
      }
    }
  }

  void _emitPhase(SyncPhase p) {
    if (_phase == p && p != SyncPhase.connecting) return;
    _phase = p;
    final e = SyncPhaseEvent(id, p);
    onEvent(e);
    if (!_events.isClosed) _events.add(e);
  }

  void _emitProgress() {
    if (_events.isClosed) return;
    var done = 0;
    var total = 0;
    for (final b in _out.values) {
      total += b.bytes.length;
      for (final i in b.sentOnce) {
        done += b.chunkLength(i);
      }
    }
    for (final b in _in.values) {
      total += b.totalBytes;
      done += b.receivedBytes;
    }
    final e = SyncProgressEvent(id, done, total);
    onEvent(e);
    _events.add(e);
  }

  // ---------------------------------------------------------------- sending

  Future<void> _sendRaw(String type, Map<String, dynamic> payload) async {
    try {
      await transport.sendMessage(
        SyncMessage(type: type, payload: {'sessionId': id, ...payload}),
      );
    } on SyncTransportException {
      // Best effort for error notifications; others handled in _send.
    } on StateError {
      // Transport disposed.
    }
  }

  Future<void> _send(String type, Map<String, dynamic> payload) async {
    if (_finished) return;
    try {
      await transport.sendMessage(
        SyncMessage(type: type, payload: {'sessionId': id, ...payload}),
      );
    } on SyncTransportException catch (e) {
      _fail(
        SyncException(
          _helloDone
              ? SyncErrorCode.transportLost
              : SyncErrorCode.peerUnavailable,
          e.message,
        ),
        notifyPeer: false,
      );
    } on StateError catch (e) {
      _fail(
        SyncException(SyncErrorCode.transportLost, e.message),
        notifyPeer: false,
      );
    }
  }

  void _sendHello() {
    _send(SyncMsg.hello, {
      'handshake': handshake.toMap(),
      'options': {'mirrorDictionaries': _mirror},
    });
  }

  void _sendOffer(OutBlob b) {
    _send(SyncMsg.offer, {
      'blobId': b.id,
      'purpose': b.purpose,
      'totalBytes': b.bytes.length,
      'chunkSize': b.chunkSize,
      'sha256': b.sha256,
    });
  }

  void _sendWant(InBlob b) {
    _send(SyncMsg.want, {
      'blobId': b.id,
      'ranges': toRanges(b.missing()),
    });
  }

  void _offerBlob(String purpose, Uint8List bytes) {
    final chunk = transport.preferredChunkSize;
    final b = OutBlob(purpose, bytes, chunk <= 0 ? 16 * 1024 : chunk);
    _out[b.id] = b;
    _sendOffer(b);
  }

  // ---------------------------------------------------------------- incoming

  void onMessage(SyncMessage m) {
    if (_finished) return;
    _lastRx = DateTime.now();
    final p = m.payload;
    try {
      switch (m.type) {
        case SyncMsg.hello:
          _onHello(p);
        case SyncMsg.helloAck:
          _onHelloAck(p);
        case SyncMsg.error:
          final code = SyncErrorCode.values.asNameMap()[p['code']] ??
              SyncErrorCode.protocol;
          _fail(
            SyncException(
              code,
              (p['message'] ?? 'peer reported $code') as String,
              fromPeer: true,
              localVersion: handshake.protocolVersion,
              peerVersion: p['peerVersion'] as int?,
            ),
            notifyPeer: false,
          );
        case SyncMsg.offer:
          _onOffer(p);
        case SyncMsg.want:
          _onWant(p);
        case SyncMsg.ack:
          _out[p['blobId']]?.acked = true;
          _out[p['blobId']]?.confirmed = true;
        case SyncMsg.ready:
          _peerReady = true;
          _advance();
        case SyncMsg.commit:
          _onCommit();
        case SyncMsg.done:
          _onDone();
      }
    } catch (e) {
      _fail(SyncException(SyncErrorCode.protocol, 'bad ${m.type}: $e'));
    }
  }


  void _onHello(Map<String, dynamic> p) {
    if (role != SyncRole.watch) return;
    if (_helloDone) {
      _send(SyncMsg.helloAck, {'handshake': handshake.toMap()});
      return;
    }
    final peer = SyncHandshake.fromMap(p['handshake'] as Map<String, dynamic>);
    if (!handshake.isCompatibleWith(peer)) {
      _fail(
        SyncException(
          SyncErrorCode.versionMismatch,
          'protocol ${handshake.protocolVersion} (min '
          '${handshake.minProtocolVersion}) vs peer ${peer.protocolVersion} '
          '(min ${peer.minProtocolVersion})',
          localVersion: handshake.protocolVersion,
          peerVersion: peer.protocolVersion,
        ),
      );
      return;
    }
    final opts = (p['options'] ?? const <String, dynamic>{}) as Map;
    _mirror = opts['mirrorDictionaries'] == true;
    _helloDone = true;
    _send(SyncMsg.helloAck, {'handshake': handshake.toMap()});
    _advance();
  }

  void _onHelloAck(Map<String, dynamic> p) {
    if (role != SyncRole.phone || _helloDone) return;
    final peer = SyncHandshake.fromMap(p['handshake'] as Map<String, dynamic>);
    if (!handshake.isCompatibleWith(peer)) {
      _fail(
        SyncException(
          SyncErrorCode.versionMismatch,
          'peer speaks protocol ${peer.protocolVersion} '
          '(min ${peer.minProtocolVersion})',
          localVersion: handshake.protocolVersion,
          peerVersion: peer.protocolVersion,
        ),
      );
      return;
    }
    _helloDone = true;
    _advance();
  }

  void _onOffer(Map<String, dynamic> p) {
    if (!_helloDone) return;
    final blobId = p['blobId'] as String;
    final purpose = p['purpose'] as String;
    final total = p['totalBytes'] as int;
    final chunkSize = p['chunkSize'] as int;
    final sha = p['sha256'] as String;
    if (total <= 0 || total > kMaxBlobBytes || chunkSize <= 0) {
      throw FormatException('bad offer sizes $total/$chunkSize');
    }
    var blob = _in[blobId];
    if (blob != null) {
      // Duplicate offer: resend ack/want only if nothing is flowing.
      if (blob.verified) {
        _send(SyncMsg.ack, {'blobId': blobId});
      } else if (blob.activeBulks == 0 &&
          DateTime.now().difference(blob.lastActivity) >=
              options.retryInterval) {
        blob.lastActivity = DateTime.now();
        _sendWant(blob);
      }
      return;
    }
    final cached = cache.take(blobId);
    if (cached != null && cached.matches(total, chunkSize, sha)) {
      blob = cached;
    } else {
      blob = InBlob(
        id: blobId,
        purpose: purpose,
        totalBytes: total,
        chunkSize: chunkSize,
        sha256: sha,
      );
    }
    blob.lastActivity = DateTime.now();
    _in[blobId] = blob;
    if (blob.verified) _onBlobVerified(blob);
    if (_phase == SyncPhase.exchangingManifests && purpose != BlobPurpose.manifest) {
      _emitPhase(SyncPhase.transferring);
    }
    _evaluate(blob);
    _emitProgress();
  }

  void _onWant(Map<String, dynamic> p) {
    final blob = _out[p['blobId']];
    if (blob == null || blob.acked) return;
    blob.confirmed = true;
    blob.wanted.addAll(fromRanges(p['ranges'], blob.chunkCount));
    _pump(blob);
  }

  Future<void> _pump(OutBlob blob) async {
    if (blob.pumping) return;
    blob.pumping = true;
    try {
      while (!_finished && !blob.acked && blob.wanted.isNotEmpty) {
        final idx = blob.wanted.toList()..sort();
        blob.wanted.clear();
        final sender = await transport.openBulk(
          BulkHeader(
            transferId: '${blob.id}#${id.hashCode}-${++_round}',
            totalBytes: blob.bytes.length,
            chunkSize: blob.chunkSize,
            metadata: {'sessionId': id, 'blobId': blob.id},
          ),
        );
        _senders.add(sender);
        try {
          for (final i in idx) {
            if (_finished || blob.acked) break;
            await sender.sendChunk(i, blob.chunk(i));
            _bytesSent += blob.chunkLength(i);
            blob.sentOnce.add(i);
            _emitProgress();
          }
          if (!_finished) await sender.end();
        } finally {
          _senders.remove(sender);
        }
      }
    } on SyncTransportException catch (e) {
      _fail(
        SyncException(SyncErrorCode.transportLost, e.message),
        notifyPeer: false,
      );
    } on StateError {
      // The receiver aborted this transfer; its error message or the idle
      // timeout decides what happens next.
    } finally {
      blob.pumping = false;
    }
  }

  /// Entry point for bulk transfers announced by the transport.
  void onBulk(IncomingBulk bulk) {
    _lastRx = DateTime.now();
    final blob = _in[bulk.header.metadata['blobId']];
    if (_finished || blob == null || blob.verified) {
      bulk.chunks.listen((_) {}, onError: (_) {});
      return;
    }
    _incoming.add(bulk);
    blob.activeBulks++;
    bulk.chunks.listen(
      (c) {
        if (_finished || blob.verified) return;
        final want = blob.expectedLength(c.index);
        if (want != c.bytes.length) return;
        _lastRx = blob.lastActivity = DateTime.now();
        if (blob.chunks.containsKey(c.index)) return;
        blob.chunks[c.index] = Uint8List.fromList(c.bytes);
        _bytesReceived += c.bytes.length;
        _emitProgress();
      },
      onDone: () {
        blob.activeBulks--;
        _incoming.remove(bulk);
        if (!_finished) _evaluate(blob);
      },
      onError: (_) {},
    );
    bulk.aborted.then((reason) {
      if (_finished) return;
      if (reason == BulkAbortReason.linkLost) {
        _fail(
          const SyncException(SyncErrorCode.transportLost, 'link lost'),
          notifyPeer: false,
        );
      }
    });
  }

  /// Checks a blob after a transfer round ended or an offer arrived.
  void _evaluate(InBlob blob) {
    if (_finished) return;
    if (blob.verified) {
      _send(SyncMsg.ack, {'blobId': blob.id});
      return;
    }
    if (blob.missing().isNotEmpty) {
      _sendWant(blob);
      return;
    }
    final data = blob.assemble();
    if (sha256Hex(data) == blob.sha256) {
      blob.data = data;
      blob.verified = true;
      _send(SyncMsg.ack, {'blobId': blob.id});
      _onBlobVerified(blob);
      return;
    }
    blob.integrityFailures++;
    blob.chunks.clear();
    if (blob.integrityFailures > options.maxIntegrityRetries) {
      _fail(
        SyncException(
          SyncErrorCode.integrityFailure,
          'SHA-256 mismatch for ${blob.purpose} blob',
        ),
      );
      return;
    }
    _sendWant(blob);
  }

  void _onBlobVerified(InBlob blob) {
    if (blob.purpose == BlobPurpose.manifest) {
      try {
        _peerManifest = SyncManifest.fromMap(
          jsonDecode(utf8.decode(blob.data!)) as Map<String, dynamic>,
        );
      } catch (e) {
        _fail(
          SyncException(SyncErrorCode.integrityFailure, 'bad manifest: $e'),
        );
        return;
      }
    }
    _advance();
  }

  // ----------------------------------------------------------------- stepper

  bool _advancing = false;
  bool _again = false;

  void _advance() {
    if (_advancing) {
      _again = true;
      return;
    }
    _advancing = true;
    () async {
      try {
        do {
          _again = false;
          await _step();
        } while (_again && !_finished);
      } on SyncException catch (e) {
        _fail(e);
      } catch (e) {
        _fail(SyncException(SyncErrorCode.protocol, 'internal: $e'));
      } finally {
        _advancing = false;
      }
    }();
  }

  Future<void> _step() async {
    if (_finished || !_helloDone) return;
    if (_local == null) {
      _emitPhase(SyncPhase.exchangingManifests);
      _local = await SyncSnapshot.capture(cards, dictionaries);
      if (_finished) return;
      _offerBlob(
        BlobPurpose.manifest,
        Uint8List.fromList(utf8.encode(jsonEncode(_local!.manifest.toMap()))),
      );
    }
    if (_peerManifest != null && _plan == null) _makePlan();
    if (_plan != null && !_staged && _inboundComplete()) {
      _emitPhase(SyncPhase.verifying);
      _stage();
    }
    if (_staged) {
      if (role == SyncRole.watch) {
        if (!_committed) _send(SyncMsg.ready, {});
      } else if (_peerReady && !_commitSent) {
        await _assertLocalUnchanged();
        if (_finished) return;
        _commitSent = true;
        _emitPhase(SyncPhase.committing);
        _send(SyncMsg.commit, {});
      }
    }
  }

  void _makePlan() {
    final mine = _local!.records;
    final theirs = resolveRecords(_peerManifest!);
    final plan = role == SyncRole.phone
        ? computeSyncPlan(
            phone: mine,
            watch: theirs,
            mirrorDictionaries: _mirror,
          )
        : computeSyncPlan(
            phone: theirs,
            watch: mine,
            mirrorDictionaries: _mirror,
          );
    _plan = plan;
    _emitPhase(SyncPhase.transferring);

    final own = plan.forRole(role);
    if (own.puts.keys.any((k) => k.$1.isCardFamily)) {
      _expectedPurposes.add(BlobPurpose.cards);
    }
    if (own.puts.keys.any((k) => !k.$1.isCardFamily)) {
      _expectedPurposes.add(BlobPurpose.dictionaries);
    }

    final peerPuts = plan.forRole(_peerRole).puts.keys.toList();
    final cardKeys = peerPuts.where((k) => k.$1.isCardFamily).toList();
    if (cardKeys.isNotEmpty) {
      final bundle = CardFolderBundle(
        rootFolderId: '',
        folders: [
          for (final k in cardKeys)
            if (k.$1 == SyncEntityKind.cardFolder)
              CardFolder.fromJson(_local!.json[k]!),
        ],
        cards: [
          for (final k in cardKeys)
            if (k.$1 == SyncEntityKind.card) CardSave.fromJson(_local!.json[k]!),
        ],
      );
      _offerBlob(
        BlobPurpose.cards,
        Uint8List.fromList(utf8.encode(bundle.toJson())),
      );
    }
    final dictKeys = peerPuts.where((k) => !k.$1.isCardFamily).toList();
    if (dictKeys.isNotEmpty) {
      final bundle = DictionaryFolderBundle(
        rootFolderId: '',
        folders: [
          for (final k in dictKeys)
            if (k.$1 == SyncEntityKind.dictionaryFolder)
              DictionaryFolder.fromJson(_local!.json[k]!),
        ],
        dictionaries: [
          for (final k in dictKeys)
            if (k.$1 == SyncEntityKind.dictionary)
              Dictionary.fromJson(_local!.json[k]!),
        ],
      );
      _offerBlob(
        BlobPurpose.dictionaries,
        Uint8List.fromList(utf8.encode(bundle.toJson())),
      );
    }
  }

  bool _inboundComplete() {
    for (final purpose in _expectedPurposes) {
      final ok = _in.values.any((b) => b.purpose == purpose && b.verified);
      if (!ok) return false;
    }
    return true;
  }

  // ----------------------------------------------------------------- staging

  void _stage() {
    final plan = _plan!;
    final own = plan.forRole(role);
    final received = <SyncKey, String>{};

    InBlob? verified(String purpose) {
      for (final b in _in.values) {
        if (b.purpose == purpose && b.verified) return b;
      }
      return null;
    }

    try {
      final cardBlob = verified(BlobPurpose.cards);
      if (cardBlob != null) {
        final bundle = CardFolderBundle.fromJson(utf8.decode(cardBlob.data!));
        for (final f in bundle.folders) {
          received[(SyncEntityKind.cardFolder, f.id)] = f.toJson();
        }
        for (final c in bundle.cards) {
          received[(SyncEntityKind.card, c.id)] = c.toJson();
        }
      }
      final dictBlob = verified(BlobPurpose.dictionaries);
      if (dictBlob != null) {
        final bundle = DictionaryFolderBundle.fromJson(
          utf8.decode(dictBlob.data!),
        );
        for (final f in bundle.folders) {
          received[(SyncEntityKind.dictionaryFolder, f.id)] = f.toJson();
        }
        for (final d in bundle.dictionaries) {
          received[(SyncEntityKind.dictionary, d.id)] = d.toJson();
        }
      }
    } on FormatException catch (e) {
      throw SyncException(SyncErrorCode.integrityFailure, 'bad bundle: $e');
    } catch (e) {
      throw SyncException(SyncErrorCode.integrityFailure, 'bad bundle: $e');
    }

    for (final e in own.puts.entries) {
      final json = received[e.key];
      if (json == null) {
        throw SyncException(
          SyncErrorCode.dataChanged,
          'peer bundle lacks ${e.key}',
        );
      }
      if (sha256Hex(utf8.encode(json)) != e.value.source.hash) {
        throw SyncException(
          SyncErrorCode.dataChanged,
          'peer changed ${e.key} during sync',
        );
      }
    }

    final finalJson = <SyncKey, String>{};
    for (final key in plan.finalLive) {
      final json = own.puts.containsKey(key) ? received[key] : _local!.json[key];
      if (json == null) {
        throw SyncException(SyncErrorCode.protocol, 'no content for $key');
      }
      finalJson[key] = json;
    }
    final rewrites = normalizeOrphans(finalJson);
    _rewrites = rewrites.length;
    _finalNormalized = {...finalJson, ...rewrites};

    _writes = {};
    for (final key in own.puts.keys) {
      _writes[key] = _finalNormalized[key]!;
    }
    for (final e in rewrites.entries) {
      _writes.putIfAbsent(e.key, () => e.value);
    }
    _staged = true;
  }

  // ------------------------------------------------------------------ commit

  Future<void> _assertLocalUnchanged() async {
    final fresh = await SyncSnapshot.capture(cards, dictionaries);
    final old = _local!.records;
    var same = fresh.records.length == old.length;
    if (same) {
      for (final e in old.entries) {
        if (fresh.records[e.key] != e.value) {
          same = false;
          break;
        }
      }
    }
    if (!same) {
      throw const SyncException(
        SyncErrorCode.dataChanged,
        'local data changed during sync',
      );
    }
  }

  void _onCommit() {
    if (role != SyncRole.watch) return;
    if (_committed) {
      _send(SyncMsg.done, {});
      return;
    }
    if (_applying) return;
    if (!_staged) {
      throw const SyncException(SyncErrorCode.protocol, 'commit before staged');
    }
    _applying = true;
    _emitPhase(SyncPhase.committing);
    () async {
      try {
        await _assertLocalUnchanged();
        await _apply();
        _committed = true;
        await _afterCommit();
        _send(SyncMsg.done, {});
        _succeed(_buildReport());
      } on SyncException catch (e) {
        _fail(e);
      } catch (e) {
        _fail(SyncException(SyncErrorCode.storeFailure, '$e'));
      }
    }();
  }

  void _onDone() {
    if (role != SyncRole.phone || !_commitSent || _applying || _committed) return;
    _applying = true;
    () async {
      try {
        await _apply();
        _committed = true;
        await _afterCommit();
        _succeed(_buildReport());
      } on SyncException catch (e) {
        _fail(e);
      } catch (e) {
        _fail(SyncException(SyncErrorCode.storeFailure, '$e'));
      }
    }();
  }

  Future<void> _afterCommit() async {
    final retention = options.tombstoneRetention;
    if (retention != null) {
      final cutoff = clock() - retention.inMilliseconds;
      await cards.pruneTombstones(cutoff);
      await dictionaries.pruneTombstones(cutoff);
    }
    cache.clear();
  }

  Future<void> _putLocal(SyncKey key, String json) async {
    switch (key.$1) {
      case SyncEntityKind.card:
        await cards.putCardFromSync(CardSave.fromJson(json));
      case SyncEntityKind.cardFolder:
        await cards.putFolderFromSync(CardFolder.fromJson(json));
      case SyncEntityKind.dictionary:
        await dictionaries.putDictionaryFromSync(Dictionary.fromJson(json));
      case SyncEntityKind.dictionaryFolder:
        await dictionaries.putFolderFromSync(DictionaryFolder.fromJson(json));
    }
  }

  Future<void> _deleteLocal(SyncTombstone t) => t.kind.isCardFamily
      ? cards.deleteFromSync(t)
      : dictionaries.deleteFromSync(t);

  Map<String, String?> _parents(Map<SyncKey, String> json, SyncEntityKind kind) {
    final out = <String, String?>{};
    for (final e in json.entries) {
      if (e.key.$1 != kind) continue;
      out[e.key.$2] =
          (jsonDecode(e.value) as Map<String, dynamic>)['parentId'] as String?;
    }
    return out;
  }

  /// Applies staged changes in dependency order. On a store failure, undoes
  /// what was applied (best effort) and throws `storeFailure`.
  Future<void> _apply() async {
    final own = _plan!.forRole(role);
    final local = _local!;
    final undo = <Future<void> Function()>[];

    Future<void> undoPut(SyncKey key, int stamp) async {
      final prev = local.json[key];
      if (prev != null) {
        await _putLocal(key, prev);
      } else {
        final old = local.tombstones[key];
        await _deleteLocal(
          old ??
              SyncTombstone(id: key.$2, kind: key.$1, deletedAt: stamp - 1),
        );
      }
    }

    Future<void> doPut(SyncKey key) async {
      final json = _writes[key]!;
      final stamp =
          (jsonDecode(json) as Map<String, dynamic>)['updatedAt'] as int? ?? 0;
      await _putLocal(key, json);
      undo.add(() => undoPut(key, stamp));
    }

    Future<void> doDelete(SyncKey key) async {
      await _deleteLocal(own.deletes[key]!);
      final prev = local.json[key];
      if (prev != null) undo.add(() => _putLocal(key, prev));
    }

    try {
      for (final k in own.deletes.keys) {
        if (!k.$1.isFolder) await doDelete(k);
      }
      for (final kind in [
        SyncEntityKind.cardFolder,
        SyncEntityKind.dictionaryFolder,
      ]) {
        final parents = _parents(_finalNormalized, kind);
        final keys = _writes.keys.where((k) => k.$1 == kind).toList()
          ..sort((a, b) {
            final da = folderDepth(a.$2, (x) => parents[x], parents.length);
            final db = folderDepth(b.$2, (x) => parents[x], parents.length);
            return da != db ? da.compareTo(db) : a.$2.compareTo(b.$2);
          });
        for (final k in keys) {
          await doPut(k);
        }
      }
      for (final k in _writes.keys.where((k) => !k.$1.isFolder)) {
        await doPut(k);
      }
      for (final kind in [
        SyncEntityKind.cardFolder,
        SyncEntityKind.dictionaryFolder,
      ]) {
        final parents = _parents(local.json, kind);
        final keys = own.deletes.keys.where((k) => k.$1 == kind).toList()
          ..sort((a, b) {
            final da = folderDepth(a.$2, (x) => parents[x], parents.length);
            final db = folderDepth(b.$2, (x) => parents[x], parents.length);
            return da != db ? db.compareTo(da) : a.$2.compareTo(b.$2);
          });
        for (final k in keys) {
          await doDelete(k);
        }
      }
    } catch (e) {
      for (final u in undo.reversed) {
        try {
          await u();
        } catch (_) {}
      }
      throw SyncException(SyncErrorCode.storeFailure, 'commit failed: $e');
    }
  }

  SyncReport _buildReport() {
    final plan = _plan!;
    SyncSideReport side(SyncSideActions a) {
      final m = <SyncEntityKind, SyncCounts>{};
      for (final e in a.puts.entries) {
        final c = m[e.key.$1] ?? const SyncCounts();
        m[e.key.$1] = e.value.replacesLive
            ? c.copyWith(updated: c.updated + 1)
            : c.copyWith(added: c.added + 1);
      }
      for (final k in a.deletes.keys) {
        final c = m[k.$1] ?? const SyncCounts();
        m[k.$1] = c.copyWith(deleted: c.deleted + 1);
      }
      return SyncSideReport(m);
    }

    return SyncReport(
      sessionId: id,
      phone: side(plan.phone),
      watch: side(plan.watch),
      conflictsResolved: plan.conflicts,
      orphansMovedToRoot: _rewrites,
      bytesSent: _bytesSent,
      bytesReceived: _bytesReceived,
      duration: _stopwatch.elapsed,
    );
  }
}
