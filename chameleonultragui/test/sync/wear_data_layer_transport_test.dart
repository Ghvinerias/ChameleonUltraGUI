import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:chameleonultragui/sync/wear_data_layer_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wear_sync/wear_sync.dart';

class FakePlatform implements WearSyncPlatform {
  FakePlatform({this.status = const WearSyncStatus(available: true)});

  WearSyncStatus status;
  final ctl = StreamController<WearSyncEvent>();
  final calls = <String>[];
  final sentMessages = <Uint8List>[];
  final sentChunks = <int, Uint8List>{};
  WearSyncException? failNext;
  bool cancelled = false;

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Future<WearSyncStatus> getStatus() async => status;

  @override
  Future<WearPeerInfo?> getPeer() async => null;

  @override
  Future<void> sendMessage(Uint8List bytes) async {
    _maybeFail();
    calls.add('sendMessage');
    sentMessages.add(bytes);
  }

  @override
  Future<void> openBulk(String transferId, Uint8List header) async {
    _maybeFail();
    calls.add('openBulk:$transferId');
  }

  @override
  Future<void> sendChunk(String transferId, int index, Uint8List bytes) async {
    _maybeFail();
    sentChunks[index] = bytes;
  }

  @override
  Future<void> endBulk(String transferId) async => calls.add('end');

  @override
  Future<void> cancelBulk(String transferId) async {
    cancelled = true;
    calls.add('cancel:$transferId');
  }

  @override
  Stream<WearSyncEvent> get events => ctl.stream;

  void emit(WearSyncEvent e) => ctl.add(e);
}

const _peer = WearPeerInfo(id: 'node1', name: 'Watch', nearby: true);

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakePlatform p;
  late WearDataLayerTransport t;

  setUp(() async {
    p = FakePlatform();
    t = await WearDataLayerTransport.create(platform: p);
  });

  tearDown(() => t.dispose());

  test('peer availability follows events', () async {
    expect(t.currentPeerState, PeerState.unavailable);
    expect(await t.getPeer(), isNull);
    final states = <PeerState>[];
    t.peerState.listen(states.add);
    p.emit(const WearPeerEvent(_peer));
    await pump();
    expect(t.currentPeerState, PeerState.available);
    expect((await t.getPeer())!.id, 'node1');
    p.emit(const WearPeerEvent(null));
    await pump();
    expect(states, [
      PeerState.unavailable,
      PeerState.available,
      PeerState.unavailable,
    ]);
  });

  test('sendMessage encodes JSON, enforces availability and size', () async {
    await expectLater(
      t.sendMessage(const SyncMessage(type: 'x')),
      throwsA(isA<SyncTransportException>()),
    );
    p.emit(const WearPeerEvent(_peer));
    await pump();
    await t.sendMessage(const SyncMessage(type: 'hello', id: '1'));
    final back = SyncMessage.fromMap(
      jsonDecode(utf8.decode(p.sentMessages.single)),
    );
    expect(back.type, 'hello');
    expect(back.id, '1');
    await expectLater(
      t.sendMessage(SyncMessage(type: 'big', payload: {'d': 'x' * 200000})),
      throwsA(isA<SyncTransportException>()),
    );
    p.failNext = const WearSyncException('failed', 'boom');
    await expectLater(
      t.sendMessage(const SyncMessage(type: 'x')),
      throwsA(isA<SyncTransportException>()),
    );
  });

  test('incoming messages decoded; malformed dropped', () async {
    final got = <SyncMessage>[];
    t.messages.listen(got.add);
    p.emit(WearMessageEvent(Uint8List.fromList([1, 2, 3])));
    p.emit(
      WearMessageEvent(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(const SyncMessage(type: 'ack', id: '9').toMap()),
          ),
        ),
      ),
    );
    await pump();
    expect(got.map((m) => m.type), ['ack']);
  });

  test('outgoing bulk: chunks, progress, end, cancel', () async {
    p.emit(const WearPeerEvent(_peer));
    await pump();
    const h = BulkHeader(transferId: 'tx', totalBytes: 10, chunkSize: 6);
    final s = await t.openBulk(h);
    final prog = <int>[];
    s.progress.listen((e) => prog.add(e.bytesTransferred));
    await s.sendChunk(0, Uint8List(6));
    await s.sendChunk(0, Uint8List(6)); // resend counts once
    await s.sendChunk(1, Uint8List(4));
    await pump();
    expect(prog, [6, 6, 10]);
    await s.end();
    expect(p.calls, ['openBulk:tx', 'end']);
    expect(() => s.sendChunk(2, Uint8List(1)), throwsStateError);

    final s2 = await t.openBulk(
      const BulkHeader(transferId: 'ty', totalBytes: 1, chunkSize: 1),
    );
    await s2.cancel();
    expect(p.calls.last, 'cancel:ty');
    expect(() => s2.sendChunk(0, Uint8List(1)), throwsStateError);
  });

  test(
    'outgoing bulk aborted by peer makes sendChunk throw StateError',
    () async {
      p.emit(const WearPeerEvent(_peer));
      await pump();
      final s = await t.openBulk(
        const BulkHeader(transferId: 'tz', totalBytes: 4, chunkSize: 2),
      );
      p.emit(const WearBulkAbortedEvent('tz', 'cancelledByPeer'));
      await pump();
      expect(() => s.sendChunk(0, Uint8List(2)), throwsStateError);
    },
  );

  test('incoming bulk: header, chunks, progress, end', () async {
    const h = BulkHeader(
      transferId: 'rx',
      totalBytes: 5,
      chunkSize: 3,
      metadata: {'kind': 'card'},
    );
    final inc = t.incomingBulk.first;
    p.emit(
      WearIncomingBulkEvent(
        'rx',
        Uint8List.fromList(utf8.encode(jsonEncode(h.toMap()))),
      ),
    );
    final b = await inc;
    expect(b.header.metadata['kind'], 'card');
    final chunks = <BulkChunk>[];
    final prog = <int>[];
    b.progress.listen((e) => prog.add(e.bytesTransferred));
    final done = b.chunks.listen(chunks.add).asFuture<void>();
    p.emit(WearChunkEvent('rx', 0, Uint8List(3)));
    p.emit(WearChunkEvent('rx', 1, Uint8List(2)));
    p.emit(const WearBulkEndEvent('rx'));
    await done;
    expect(chunks.map((c) => c.index), [0, 1]);
    expect(prog, [3, 5]);
  });

  test('incoming chunks arriving before listen are buffered', () async {
    const h = BulkHeader(transferId: 'b', totalBytes: 2, chunkSize: 2);
    final inc = t.incomingBulk.first;
    p.emit(
      WearIncomingBulkEvent(
        'b',
        Uint8List.fromList(utf8.encode(jsonEncode(h.toMap()))),
      ),
    );
    final b = await inc;
    p.emit(WearChunkEvent('b', 0, Uint8List(2)));
    p.emit(const WearBulkEndEvent('b'));
    await pump();
    expect((await b.chunks.toList()).length, 1);
  });

  test('incoming abort reasons and local cancel', () async {
    Future<IncomingBulk> open(String id) async {
      final f = t.incomingBulk.first;
      p.emit(
        WearIncomingBulkEvent(
          id,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode(
                BulkHeader(transferId: id, totalBytes: 9, chunkSize: 3).toMap(),
              ),
            ),
          ),
        ),
      );
      return f;
    }

    final a = await open('a');
    p.emit(const WearBulkAbortedEvent('a', 'linkLost'));
    expect(await a.aborted, BulkAbortReason.linkLost);
    expect(await a.chunks.toList(), isEmpty);

    final c = await open('c');
    p.emit(const WearBulkAbortedEvent('c', 'cancelledByPeer'));
    expect(await c.aborted, BulkAbortReason.cancelledByPeer);

    final d = await open('d');
    await d.cancel();
    expect(await d.aborted, BulkAbortReason.cancelledByLocal);
    expect(p.calls, contains('cancel:d'));
  });

  test('unavailable Play Services degrades without throwing', () async {
    final up = FakePlatform(
      status: const WearSyncStatus(available: false, reason: 'play_services_9'),
    );
    final u = await WearDataLayerTransport.create(platform: up);
    expect(u.isSupported, isFalse);
    expect(u.currentPeerState, PeerState.unavailable);
    expect(await u.getPeer(), isNull);
    await expectLater(
      u.sendMessage(const SyncMessage(type: 'x')),
      throwsA(isA<SyncTransportException>()),
    );
    await u.dispose();
  });

  test('dispose then use throws StateError', () async {
    await t.dispose();
    expect(() => t.getPeer(), throwsStateError);
    expect(() => t.sendMessage(const SyncMessage(type: 'x')), throwsStateError);
  });
}
