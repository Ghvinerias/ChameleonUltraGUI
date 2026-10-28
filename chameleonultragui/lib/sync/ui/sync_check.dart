// On-device link diagnostic: ping round trip, then a payload each way over the
// bulk path with throughput and a SHA-256 integrity check. Both devices run a
// responder while their sync screen is open; either side can start a check.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:crypto/crypto.dart';

enum SyncCheckStage { ping, send, receive }

class SyncCheckTransfer {
  const SyncCheckTransfer({
    this.ok = false,
    this.skipped = false,
    this.bytes = 0,
    this.elapsed = Duration.zero,
    this.error,
  });

  const SyncCheckTransfer.skipped() : this(skipped: true);

  final bool ok;
  final bool skipped;
  final int bytes;
  final Duration elapsed;
  final String? error;

  double get bytesPerSecond => elapsed.inMicroseconds <= 0
      ? 0
      : bytes * 1000000 / elapsed.inMicroseconds;
}

class SyncCheckResult {
  const SyncCheckResult({
    required this.pingOk,
    required this.pingSamples,
    required this.pingAverage,
    required this.send,
    required this.receive,
    this.pingError,
  });

  final bool pingOk;
  final int pingSamples;
  final Duration pingAverage;
  final String? pingError;

  /// This device -> the other device.
  final SyncCheckTransfer send;

  /// The other device -> this device.
  final SyncCheckTransfer receive;

  bool get passed => pingOk && send.ok && receive.ok;
}

class _Received {
  _Received(this.ok, this.bytes, this.elapsed, this.error);
  final bool ok;
  final int bytes;
  final Duration elapsed;
  final String? error;
}

class SyncCheck {
  SyncCheck({
    required this.transport,
    this.payloadBytes = 1024 * 1024,
    this.pingCount = 3,
    this.pingTimeout = const Duration(seconds: 4),
    this.transferTimeout = const Duration(seconds: 30),
  });

  /// The check view of a [SyncTransportSplit].
  final SyncTransport transport;
  final int payloadBytes;
  final int pingCount;
  final Duration pingTimeout;
  final Duration transferTimeout;

  StreamSubscription<SyncMessage>? _msgSub;
  StreamSubscription<IncomingBulk>? _bulkSub;
  bool _disposed = false;
  int _seq = 0;
  final String _salt = Random().nextInt(1 << 31).toRadixString(16);

  final Map<String, Completer<void>> _pongs = {};
  final Map<String, Completer<Map<String, dynamic>>> _results = {};
  final Map<String, Completer<_Received>> _received = {};

  /// Starts answering the peer's pings, pulls and pushes. Idempotent.
  void startResponder() {
    if (_msgSub != null || _disposed) return;
    _msgSub = transport.messages.listen(_onMessage);
    _bulkSub = transport.incomingBulk.listen(_onBulk);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _msgSub?.cancel();
    await _bulkSub?.cancel();
    for (final c in [..._pongs.values]) {
      if (!c.isCompleted) c.completeError(StateError('disposed'));
    }
    for (final c in [..._results.values]) {
      if (!c.isCompleted) c.completeError(StateError('disposed'));
    }
    for (final c in [..._received.values]) {
      if (!c.isCompleted) {
        c.complete(_Received(false, 0, Duration.zero, 'stopped'));
      }
    }
  }

  String _nonce() => '$_salt-${_seq++}';

  /// Deterministic payload so either side can recompute the digest.
  static Uint8List payloadFor(int bytes, String nonce) {
    var x = nonce.hashCode & 0x7fffffff | 1;
    final out = Uint8List(bytes);
    for (var i = 0; i < bytes; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      out[i] = x >> 16;
    }
    return out;
  }

  // ----------------------------------------------------------------- run

  Future<SyncCheckResult> run({void Function(SyncCheckStage)? onStage}) async {
    startResponder();
    onStage?.call(SyncCheckStage.ping);
    final rtts = <Duration>[];
    String? pingError;
    for (var i = 0; i < pingCount; i++) {
      try {
        rtts.add(await _ping());
      } on TimeoutException {
        pingError = 'no answer from the other device';
        break;
      } catch (e) {
        pingError = _describe(e);
        break;
      }
    }
    final pingOk = pingError == null && rtts.isNotEmpty;
    final avg = rtts.isEmpty
        ? Duration.zero
        : Duration(
            microseconds:
                rtts.fold(0, (a, d) => a + d.inMicroseconds) ~/ rtts.length,
          );
    if (!pingOk) {
      return SyncCheckResult(
        pingOk: false,
        pingSamples: rtts.length,
        pingAverage: avg,
        pingError: pingError ?? 'failed',
        send: const SyncCheckTransfer.skipped(),
        receive: const SyncCheckTransfer.skipped(),
      );
    }
    onStage?.call(SyncCheckStage.send);
    final send = await _push();
    onStage?.call(SyncCheckStage.receive);
    final receive = await _pull();
    return SyncCheckResult(
      pingOk: true,
      pingSamples: rtts.length,
      pingAverage: avg,
      send: send,
      receive: receive,
    );
  }

  String _describe(Object e) => e is SyncTransportException
      ? e.message
      : e is StateError
      ? 'link closed'
      : '$e';

  Future<Duration> _ping() async {
    final n = _nonce();
    final c = _pongs[n] = Completer<void>();
    final sw = Stopwatch()..start();
    try {
      await transport.sendMessage(
        SyncMessage(type: '${kCheckMessagePrefix}ping', payload: {'nonce': n}),
      );
      await c.future.timeout(pingTimeout);
      return sw.elapsed;
    } finally {
      _pongs.remove(n);
    }
  }

  BulkHeader _header(String nonce, String mode, Uint8List data) => BulkHeader(
    transferId: 'check-$nonce',
    totalBytes: data.length,
    chunkSize: transport.preferredChunkSize <= 0
        ? 16 * 1024
        : transport.preferredChunkSize,
    metadata: {
      kCheckBulkKey: '1',
      'nonce': nonce,
      'mode': mode,
      'sha256': sha256.convert(data).toString(),
    },
  );

  Future<void> _sendPayload(BulkHeader header, Uint8List data) async {
    final sender = await transport.openBulk(header);
    final size = header.chunkSize;
    try {
      for (var i = 0; i < header.chunkCount; i++) {
        final end = min(data.length, (i + 1) * size);
        await sender.sendChunk(i, Uint8List.sublistView(data, i * size, end));
      }
      await sender.end();
    } catch (_) {
      await sender.cancel().catchError((_) {});
      rethrow;
    }
  }

  /// This device -> peer.
  Future<SyncCheckTransfer> _push() async {
    final n = _nonce();
    final data = payloadFor(payloadBytes, n);
    final result = _results[n] = Completer<Map<String, dynamic>>();
    final sw = Stopwatch()..start();
    try {
      await _sendPayload(_header(n, 'push', data), data);
      final r = await result.future.timeout(transferTimeout);
      sw.stop();
      if (r['ok'] == true) {
        return SyncCheckTransfer(
          ok: true,
          bytes: data.length,
          elapsed: sw.elapsed,
        );
      }
      return SyncCheckTransfer(
        bytes: data.length,
        elapsed: sw.elapsed,
        error: 'peer rejected it: ${r['error'] ?? 'unknown'}',
      );
    } on TimeoutException {
      return const SyncCheckTransfer(error: 'no confirmation from the peer');
    } catch (e) {
      return SyncCheckTransfer(error: _describe(e));
    } finally {
      _results.remove(n);
    }
  }

  /// Peer -> this device.
  Future<SyncCheckTransfer> _pull() async {
    final n = _nonce();
    final rx = _received.putIfAbsent(n, Completer<_Received>.new);
    try {
      await transport.sendMessage(
        SyncMessage(
          type: '${kCheckMessagePrefix}pull',
          payload: {'nonce': n, 'bytes': payloadBytes},
        ),
      );
      final r = await rx.future.timeout(transferTimeout);
      return SyncCheckTransfer(
        ok: r.ok,
        bytes: r.bytes,
        elapsed: r.elapsed,
        error: r.error,
      );
    } on TimeoutException {
      return const SyncCheckTransfer(error: 'no data from the peer');
    } catch (e) {
      return SyncCheckTransfer(error: _describe(e));
    } finally {
      _received.remove(n);
    }
  }

  // ------------------------------------------------------------ responder

  void _onMessage(SyncMessage m) {
    if (_disposed) return;
    final n = m.payload['nonce'];
    if (n is! String) return;
    switch (m.type) {
      case '${kCheckMessagePrefix}ping':
        _reply('pong', {'nonce': n});
      case '${kCheckMessagePrefix}pong':
        final c = _pongs[n];
        if (c != null && !c.isCompleted) c.complete();
      case '${kCheckMessagePrefix}result':
        final c = _results[n];
        if (c != null && !c.isCompleted) c.complete(m.payload);
      case '${kCheckMessagePrefix}pull':
        final bytes = m.payload['bytes'];
        if (bytes is int && bytes > 0 && bytes <= 16 * 1024 * 1024) {
          final data = payloadFor(bytes, n);
          _sendPayload(_header(n, 'pull', data), data).catchError((_) {});
        }
    }
  }

  void _reply(String type, Map<String, dynamic> payload) {
    transport
        .sendMessage(
          SyncMessage(type: '$kCheckMessagePrefix$type', payload: payload),
        )
        .catchError((_) {});
  }

  void _onBulk(IncomingBulk b) {
    if (_disposed) return;
    final nonce = b.header.metadata['nonce'] ?? '';
    final mode = b.header.metadata['mode'];
    final done = _received.putIfAbsent(nonce, Completer<_Received>.new);
    final chunks = <int, Uint8List>{};
    final sw = Stopwatch()..start();
    var aborted = false;
    b.aborted.then((_) => aborted = true);

    void finish(_Received r) {
      if (!done.isCompleted) done.complete(r);
      if (mode == 'push') {
        _received.remove(nonce);
        _reply('result', {
          'nonce': nonce,
          'ok': r.ok,
          if (r.error != null) 'error': r.error,
        });
      }
    }

    b.chunks.listen(
      (c) => chunks.putIfAbsent(c.index, () => c.bytes),
      onError: (_) {},
      onDone: () async {
        // Let a pending abort callback run before judging the stream.
        await Future<void>.delayed(Duration.zero);
        sw.stop();
        final h = b.header;
        if (aborted) {
          return finish(_Received(false, 0, sw.elapsed, 'transfer aborted'));
        }
        if (chunks.length != h.chunkCount) {
          return finish(
            _Received(
              false,
              0,
              sw.elapsed,
              'missing ${h.chunkCount - chunks.length} of ${h.chunkCount} '
              'chunks',
            ),
          );
        }
        final out = BytesBuilder(copy: false);
        for (var i = 0; i < h.chunkCount; i++) {
          out.add(chunks[i]!);
        }
        final all = out.takeBytes();
        if (all.length != h.totalBytes ||
            sha256.convert(all).toString() != h.metadata['sha256']) {
          return finish(
            _Received(false, all.length, sw.elapsed, 'integrity check failed'),
          );
        }
        finish(_Received(true, all.length, sw.elapsed, null));
      },
    );
  }
}
