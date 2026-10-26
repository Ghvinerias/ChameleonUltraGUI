import 'dart:typed_data';

import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_sync_transport.dart';

Future<List<BulkChunk>> _collect(IncomingBulk rx) => rx.chunks.toList();

Future<(BulkSender, IncomingBulk)> _open(
  InMemorySyncTransport tx,
  InMemorySyncTransport rx,
  int total, {
  int chunkSize = 4,
}) async {
  final incoming = rx.incomingBulk.first;
  final sender = await tx.openBulk(
    BulkHeader(transferId: 't1', totalBytes: total, chunkSize: chunkSize),
  );
  return (sender, await incoming);
}

void main() {
  test('messages round-trip as JSON', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final got = b.messages.first;
    await a.sendMessage(
      const SyncMessage(
        type: 'hello',
        id: '1',
        payload: {
          'n': 1,
          'l': [1, 2],
        },
      ),
    );
    final m = await got;
    expect(m.type, 'hello');
    expect(m.payload['n'], 1);
  });

  test('oversized message and unavailable peer are rejected', () async {
    final (a, b) = InMemorySyncTransport.pair(maxMessageBytes: 32);
    await expectLater(
      a.sendMessage(SyncMessage(type: 'x', payload: {'d': 'y' * 100})),
      throwsA(isA<SyncTransportException>()),
    );
    a.setPeerAvailable(false);
    expect(b.currentPeerState, PeerState.unavailable);
    expect(await a.getPeer(), isNull);
    await expectLater(
      a.sendMessage(const SyncMessage(type: 'x')),
      throwsA(isA<SyncTransportException>()),
    );
    a.setPeerAvailable(true);
    expect(await b.getPeer(), isNotNull);
  });

  test('message hook can duplicate and drop', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final received = <String>[];
    b.messages.listen((m) => received.add(m.type));
    a.messageHook = (m) =>
        m.type == 'dup' ? ChunkFate.duplicate : ChunkFate.drop;
    await a.sendMessage(const SyncMessage(type: 'dup'));
    await a.sendMessage(const SyncMessage(type: 'lost'));
    await Future<void>.delayed(Duration.zero);
    expect(received, ['dup', 'dup']);
  });

  test('bulk delivers all chunks with progress', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final (tx, rx) = await _open(a, b, 10);
    final progress = <int>[];
    rx.progress.listen((p) => progress.add(p.bytesTransferred));
    final chunks = _collect(rx);
    await tx.sendChunk(0, Uint8List.fromList([0, 1, 2, 3]));
    await tx.sendChunk(1, Uint8List.fromList([4, 5, 6, 7]));
    await tx.sendChunk(2, Uint8List.fromList([8, 9]));
    await tx.end();
    final got = await chunks;
    expect(got.map((c) => c.index), [0, 1, 2]);
    expect(progress.last, 10);
  });

  test('chunk hook: drop, duplicate, reorder', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final (tx, rx) = await _open(a, b, 16);
    a.chunkHook = (c) => switch (c.index) {
      0 => ChunkFate.drop,
      1 => ChunkFate.duplicate,
      2 => ChunkFate.held,
      _ => ChunkFate.deliver,
    };
    final chunks = _collect(rx);
    for (var i = 0; i < 4; i++) {
      await tx.sendChunk(i, Uint8List.fromList([i, i, i, i]));
    }
    a.flushHeld();
    await tx.end();
    expect((await chunks).map((c) => c.index), [1, 1, 3, 2]);
  });

  test('resend of a dropped chunk completes the transfer (resume)', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final (tx, rx) = await _open(a, b, 8);
    var drop = true;
    a.chunkHook = (c) =>
        (c.index == 0 && drop) ? ChunkFate.drop : ChunkFate.deliver;
    final chunks = _collect(rx);
    await tx.sendChunk(0, Uint8List(4));
    drop = false;
    await tx.sendChunk(0, Uint8List(4));
    await tx.sendChunk(1, Uint8List(4));
    await tx.end();
    expect((await chunks).map((c) => c.index), [0, 1]);
  });

  test('cancel from sender aborts the receiver', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final (tx, rx) = await _open(a, b, 8);
    await tx.cancel();
    expect(await rx.aborted, BulkAbortReason.cancelledByPeer);
    await expectLater(tx.sendChunk(0, Uint8List(4)), throwsStateError);
  });

  test('cancel from receiver stops the sender', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final (tx, rx) = await _open(a, b, 8);
    await rx.cancel();
    await Future<void>.delayed(Duration.zero);
    await expectLater(tx.sendChunk(0, Uint8List(4)), throwsStateError);
  });

  test('link loss aborts in-flight transfers', () async {
    final (a, b) = InMemorySyncTransport.pair();
    final (_, rx) = await _open(a, b, 8);
    a.setPeerAvailable(false);
    expect(await rx.aborted, BulkAbortReason.linkLost);
  });

  test('sync models round-trip', () {
    const h = SyncHandshake(role: SyncRole.watch, deviceId: 'w');
    final h2 = SyncHandshake.fromMap(h.toMap());
    expect(h2.protocolVersion, kSyncProtocolVersion);
    expect(h.isCompatibleWith(h2), isTrue);
    expect(
      const BulkHeader(
        transferId: 'a',
        totalBytes: 10,
        chunkSize: 4,
      ).chunkCount,
      3,
    );
  });
}
