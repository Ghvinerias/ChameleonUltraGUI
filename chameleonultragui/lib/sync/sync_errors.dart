// Typed sync failures (no localized strings). Track T4.

enum SyncErrorCode {
  /// No paired device reachable (at start, or never answered the handshake).
  peerUnavailable,

  /// Protocol versions are not compatible; see [SyncException.localVersion]
  /// and [SyncException.peerVersion].
  versionMismatch,

  /// Cancelled locally or by the peer. Nothing was applied.
  cancelled,

  /// A blob failed SHA-256 verification (after retries) or was malformed.
  integrityFailure,

  /// The link dropped or a send failed mid-session.
  transportLost,

  /// The peer went silent for longer than `SyncOptions.idleTimeout`.
  timeout,

  /// A replica changed while the sync was running; nothing was applied.
  /// Retrying is safe.
  dataChanged,

  /// The peer violated the protocol.
  protocol,

  /// A store write failed during commit; the engine rolled back best-effort.
  storeFailure,
}

class SyncException implements Exception {
  final SyncErrorCode code;

  /// Developer-facing detail, never shown to users.
  final String message;

  /// True when the peer reported the failure.
  final bool fromPeer;

  final int? localVersion;
  final int? peerVersion;

  const SyncException(
    this.code,
    this.message, {
    this.fromPeer = false,
    this.localVersion,
    this.peerVersion,
  });

  @override
  String toString() => 'SyncException(${code.name}): $message';
}
