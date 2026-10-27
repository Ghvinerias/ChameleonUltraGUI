// Pure-Dart phone <-> watch sync engine (Track T4).
//
// Both devices run a [SyncEngine] over a `SyncTransport` and their local
// `CardStore` / `DictionaryStore`. The watch calls [SyncEngine.start] and
// answers; the phone calls [SyncEngine.startSync]. See `sync_run.dart` for the
// protocol and `docs/wear-contracts.md` ("Sync engine") for the semantics.
import 'dart:async';

import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/sync/sync_blob.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_report.dart';
import 'package:chameleonultragui/sync/sync_run.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:chameleonultragui/sync/sync_types.dart';
import 'package:uuid/uuid.dart';

export 'package:chameleonultragui/sync/sync_errors.dart';
export 'package:chameleonultragui/sync/sync_records.dart'
    show computeSyncPlan, resolveRecords, SyncPlan, SyncRecord, SyncKey;
export 'package:chameleonultragui/sync/sync_report.dart';
export 'package:chameleonultragui/sync/sync_types.dart';

class SyncEngine {
  SyncEngine({
    required this.role,
    required this.transport,
    required this.cards,
    required this.dictionaries,
    this.options = const SyncOptions(),
    this.deviceId = '',
    this.appVersion = '',
    int Function()? clock,
    int protocolVersion = kSyncProtocolVersion,
    int minProtocolVersion = kSyncMinProtocolVersion,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _handshake = SyncHandshake(
         protocolVersion: protocolVersion,
         minProtocolVersion: minProtocolVersion,
         role: role,
         deviceId: deviceId,
         appVersion: appVersion,
         capabilities: const ['dictionaryMirror'],
       );

  final SyncRole role;
  final SyncTransport transport;
  final CardStore cards;
  final DictionaryStore dictionaries;
  final SyncOptions options;
  final String deviceId;
  final String appVersion;
  final int Function() _clock;
  final SyncHandshake _handshake;

  final SyncResumeCache resumeCache = SyncResumeCache();
  final _events = StreamController<SyncEvent>.broadcast();
  final _sessions = StreamController<SyncSession>.broadcast();
  final Set<String> _recentlyDone = {};
  StreamSubscription<SyncMessage>? _msgSub;
  StreamSubscription<IncomingBulk>? _bulkSub;
  SyncRun? _run;
  bool _disposed = false;

  /// Events of every session on this device (phone- or peer-initiated).
  Stream<SyncEvent> get events => _events.stream;

  /// Sessions started by the peer (watch side).
  Stream<SyncSession> get incomingSessions => _sessions.stream;

  SyncSession? get activeSession => _run;
  bool get isSyncing => _run != null;

  /// Starts listening to the transport. Call on both devices before the
  /// phone syncs (idempotent).
  void start() {
    if (_msgSub != null) return;
    _msgSub = transport.messages.listen(_onMessage);
    _bulkSub = transport.incomingBulk.listen((b) {
      final run = _run;
      final sid = b.header.metadata['sessionId'];
      if (run != null && run.id == sid) {
        run.onBulk(b);
      } else {
        b.chunks.listen((_) {}, onError: (_) {});
      }
    });
  }

  /// Phone only: runs one sync. Throws [StateError] on the watch or while
  /// another session is active.
  SyncSession startSync({bool? mirrorDictionaries}) {
    if (role != SyncRole.phone) {
      throw StateError('only the phone initiates a sync');
    }
    if (_disposed) throw StateError('engine disposed');
    if (_run != null) throw StateError('a sync is already running');
    start();
    final run = _newRun(
      const Uuid().v4(),
      mirrorDictionaries == null
          ? options
          : options.copyWith(mirrorDictionaries: mirrorDictionaries),
    );
    _run = run;
    run.beginAsPhone();
    return run;
  }

  /// Convenience: [startSync] and wait for the report.
  Future<SyncReport> sync({bool? mirrorDictionaries}) =>
      startSync(mirrorDictionaries: mirrorDictionaries).result;

  /// Drops partially received blobs kept for resume.
  void clearResumeCache() => resumeCache.clear();

  SyncRun _newRun(String id, SyncOptions opts) => SyncRun(
    id: id,
    role: role,
    transport: transport,
    cards: cards,
    dictionaries: dictionaries,
    options: opts,
    handshake: _handshake,
    cache: resumeCache,
    clock: _clock,
    onEvent: (e) {
      if (!_events.isClosed) _events.add(e);
    },
    onFinished: (run, ok) {
      if (identical(_run, run)) _run = null;
      if (ok && role == SyncRole.watch) {
        _recentlyDone.add(run.id);
        if (_recentlyDone.length > 8) {
          _recentlyDone.remove(_recentlyDone.first);
        }
      }
    },
  );

  void _onMessage(SyncMessage m) {
    if (_disposed) return;
    final sid = m.payload['sessionId'];
    if (sid is! String) return;
    final run = _run;
    if (run != null && run.id == sid) {
      run.onMessage(m);
      return;
    }
    if (role != SyncRole.watch) return;
    if (m.type == SyncMsg.hello) {
      if (_recentlyDone.contains(sid)) return;
      run?.supersede();
      final fresh = _newRun(sid, options);
      _run = fresh;
      _sessions.add(fresh);
      fresh.beginAsWatch(m);
    } else if (m.type == SyncMsg.commit && _recentlyDone.contains(sid)) {
      transport
          .sendMessage(
            SyncMessage(type: SyncMsg.done, payload: {'sessionId': sid}),
          )
          .catchError((_) {});
    }
  }

  /// Cancels the active session and stops listening. Does not dispose the
  /// transport.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _run?.cancel();
    await _msgSub?.cancel();
    await _bulkSub?.cancel();
    await _events.close();
    await _sessions.close();
  }
}
