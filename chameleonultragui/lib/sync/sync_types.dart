// Public option/event/session types of the sync engine (T4).
import 'package:chameleonultragui/sync/sync_errors.dart';
import 'package:chameleonultragui/sync/sync_report.dart';

class SyncOptions {
  /// Phone-authoritative dictionaries (and dictionary folders). Only the
  /// phone's value matters; the watch adopts it from the handshake.
  final bool mirrorDictionaries;

  /// How often unanswered control messages and stalled transfers are retried.
  final Duration retryInterval;

  /// No traffic from the peer for this long fails the session (`timeout`).
  final Duration idleTimeout;

  /// The phone gives up on an unanswered handshake after this long
  /// (`peerUnavailable`).
  final Duration handshakeTimeout;

  /// How often a blob whose SHA-256 does not match is re-requested in full.
  final int maxIntegrityRetries;

  /// When set, tombstones older than this are pruned on each device after a
  /// successful commit.
  final Duration? tombstoneRetention;

  const SyncOptions({
    this.mirrorDictionaries = false,
    this.retryInterval = const Duration(seconds: 2),
    this.idleTimeout = const Duration(seconds: 30),
    this.handshakeTimeout = const Duration(seconds: 10),
    this.maxIntegrityRetries = 2,
    this.tombstoneRetention,
  });

  SyncOptions copyWith({bool? mirrorDictionaries}) => SyncOptions(
    mirrorDictionaries: mirrorDictionaries ?? this.mirrorDictionaries,
    retryInterval: retryInterval,
    idleTimeout: idleTimeout,
    handshakeTimeout: handshakeTimeout,
    maxIntegrityRetries: maxIntegrityRetries,
    tombstoneRetention: tombstoneRetention,
  );
}

enum SyncPhase {
  connecting,
  exchangingManifests,
  transferring,
  verifying,
  committing,
  done,
}

sealed class SyncEvent {
  final String sessionId;
  const SyncEvent(this.sessionId);
}

class SyncPhaseEvent extends SyncEvent {
  final SyncPhase phase;
  const SyncPhaseEvent(super.sessionId, this.phase);
}

/// Byte progress over both directions. [bytesTotal] grows as the peer's
/// offers arrive.
class SyncProgressEvent extends SyncEvent {
  final int bytesTransferred;
  final int bytesTotal;
  const SyncProgressEvent(
    super.sessionId,
    this.bytesTransferred,
    this.bytesTotal,
  );

  double get fraction => bytesTotal == 0 ? 0 : bytesTransferred / bytesTotal;
}

class SyncDoneEvent extends SyncEvent {
  final SyncReport report;
  const SyncDoneEvent(super.sessionId, this.report);
}

class SyncFailedEvent extends SyncEvent {
  final SyncException error;
  const SyncFailedEvent(super.sessionId, this.error);
}

/// One sync run, on either side.
abstract class SyncSession {
  String get id;
  SyncPhase get phase;

  /// Broadcast; the last event is [SyncDoneEvent] or [SyncFailedEvent].
  Stream<SyncEvent> get events;

  /// Completes with the report, or with a [SyncException].
  Future<SyncReport> get result;

  /// Cancels the run (and tells the peer). Returns false when it is too late
  /// (commit already started) or the run already ended. Nothing is applied
  /// on a cancelled run.
  bool cancel();
}
