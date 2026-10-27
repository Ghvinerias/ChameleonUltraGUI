import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/sync/sync_engine.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/in_memory_sync_transport.dart';
import 'sync_harness.dart';

/// Seeds `n` cards of ~2 KB of JSON each on [r].
Future<void> _bulk(Replica r, String prefix, int n, {int stamp = 5}) async {
  final rnd = Random(prefix.hashCode);
  for (var i = 0; i < n; i++) {
    await r.cards.putCardFromSync(
      CardSave(
        id: '$prefix$i',
        uid: '0102',
        name: '$prefix$i',
        tag: TagType.mifare1K,
        updatedAt: stamp,
        data: [
          for (var b = 0; b < 16; b++)
            Uint8List.fromList([for (var k = 0; k < 16; k++) rnd.nextInt(256)]),
        ],
      ),
    );
  }
}

Future<(Replica, Replica)> _populated() async {
  final p = Replica();
  final w = Replica();
  await _bulk(p, 'p', 40);
  await _bulk(w, 'w', 40);
  return (p, w);
}

void main() {
  group('lossy bulk', () {
    test('dropped chunks are re-requested', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w, chunkSize: 2048);
      final rnd = Random(1);
      pair.phoneTransport.chunkHook = (_) =>
          rnd.nextDouble() < 0.35 ? ChunkFate.drop : ChunkFate.deliver;
      pair.watchTransport.chunkHook = (_) =>
          rnd.nextDouble() < 0.35 ? ChunkFate.drop : ChunkFate.deliver;
      final r = await pair.sync();
      expect(p.dump(), w.dump());
      expect(p.dump().length, 80);
      expect(r.phone.totalAdded, 40);
      await pair.dispose();
    });

    test('duplicated chunks are harmless', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w, chunkSize: 2048);
      pair.phoneTransport.chunkHook = (_) => ChunkFate.duplicate;
      pair.watchTransport.chunkHook = (_) => ChunkFate.duplicate;
      await pair.sync();
      expect(p.dump(), w.dump());
      await pair.dispose();
    });

    test('reordered chunks are reassembled', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w, chunkSize: 2048);
      for (final t in [pair.phoneTransport, pair.watchTransport]) {
        final heldOnce = <String>{};
        t.chunkHook = (c) {
          if (c.index % 5 == 1 &&
              heldOnce.add('${c.transferId.split('#').first}/${c.index}')) {
            return ChunkFate.held;
          }
          if (c.index % 5 == 3) {
            scheduleMicrotask(t.flushHeld);
          }
          return ChunkFate.deliver;
        };
      }
      await pair.sync();
      expect(p.dump(), w.dump());
      await pair.dispose();
    });

    test('lost control messages are retried', () async {
      for (final seed in [1, 2, 3, 4]) {
        final (p, w) = await _populated();
        final pair = SyncPair(phone: p, watch: w, chunkSize: 4096);
        final rnd = Random(seed);
        ChunkFate lossy(SyncMessage m) =>
            rnd.nextDouble() < 0.3 ? ChunkFate.drop : ChunkFate.deliver;
        pair.phoneTransport.messageHook = lossy;
        pair.watchTransport.messageHook = lossy;
        await pair.sync();
        expect(p.dump(), w.dump(), reason: 'seed $seed');
        await pair.dispose();
      }
    });

    test('everything at once', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w, chunkSize: 1024);
      final rnd = Random(99);
      ChunkFate chunkFate(BulkChunk c) {
        final x = rnd.nextDouble();
        if (x < 0.2) return ChunkFate.drop;
        if (x < 0.4) return ChunkFate.duplicate;
        if (x < 0.5) return ChunkFate.held;
        return ChunkFate.deliver;
      }

      for (final t in [pair.phoneTransport, pair.watchTransport]) {
        t.chunkHook = (c) {
          if (rnd.nextDouble() < 0.1) scheduleMicrotask(t.flushHeld);
          return chunkFate(c);
        };
        t.messageHook = (m) => rnd.nextDouble() < 0.2
            ? ChunkFate.drop
            : (rnd.nextDouble() < 0.2
                  ? ChunkFate.duplicate
                  : ChunkFate.deliver);
      }
      await pair.sync();
      expect(p.dump(), w.dump());
      await pair.dispose();
    });
  });

  group('interruption', () {
    test(
      'link loss mid-transfer, then a resumed sync fetches only the rest',
      () async {
        final (p, w) = await _populated();
        final pair = SyncPair(phone: p, watch: w, chunkSize: 2048);
        var cardChunks = 0;
        var total = 0;
        var cut = true;
        pair.phoneTransport.chunkHook = (c) {
          if (!c.transferId.startsWith('cards:')) return ChunkFate.deliver;
          cardChunks++;
          if (cut && cardChunks == 6) {
            pair.phoneTransport.setPeerAvailable(false);
            return ChunkFate.drop;
          }
          return ChunkFate.deliver;
        };
        final before = (p.dump(), w.dump());
        await expectLater(
          pair.sync(),
          throwsA(
            isA<SyncException>().having(
              (e) => e.code,
              'code',
              SyncErrorCode.transportLost,
            ),
          ),
        );
        expect(p.dump(), before.$1);
        expect(w.dump(), before.$2);
        expect(pair.watchEngine.resumeCache.length, greaterThan(0));

        // Link comes back; count the bundle chunks of the retry.
        pair.phoneTransport.setPeerAvailable(true);
        cut = false;
        cardChunks = 0;
        final seen = <int>{};
        pair.phoneTransport.chunkHook = (c) {
          if (c.transferId.startsWith('cards:')) {
            cardChunks++;
            seen.add(c.index);
          }
          return ChunkFate.deliver;
        };
        await pair.sync();
        expect(p.dump(), w.dump());
        // Offer header total tells us the full chunk count.
        total =
            ((pair.phoneTransport.sentMessages
                            .where(
                              (m) =>
                                  m.type == 'sync.offer' &&
                                  m.payload['purpose'] == 'cards',
                            )
                            .last
                            .payload['totalBytes']
                        as int) /
                    2048)
                .ceil();
        expect(cardChunks, lessThan(total));
        expect(cardChunks, total - 5); // the five delivered chunks were kept
        await pair.dispose();
      },
    );

    test('cancelled mid-transfer leaves both stores untouched', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w, chunkSize: 1024);
      final before = (p.dump(), w.dump());
      final writesBefore = (p.cards.writes, w.cards.writes);
      final watchSession = pair.watchEngine.incomingSessions.first;
      final session = pair.phoneEngine.startSync();
      session.events.listen((e) {
        if (e is SyncProgressEvent && e.bytesTransferred > 4000) {
          session.cancel();
        }
      });
      await expectLater(
        session.result,
        throwsA(
          isA<SyncException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.cancelled,
          ),
        ),
      );
      final ws = await watchSession;
      await expectLater(
        ws.result,
        throwsA(
          isA<SyncException>()
              .having((e) => e.code, 'code', SyncErrorCode.cancelled)
              .having((e) => e.fromPeer, 'fromPeer', isTrue),
        ),
      );
      expect(p.dump(), before.$1);
      expect(w.dump(), before.$2);
      expect((p.cards.writes, w.cards.writes), writesBefore);
      expect(pair.phoneEngine.isSyncing, isFalse);
      // A fresh sync afterwards works.
      await pair.sync();
      expect(p.dump(), w.dump());
      await pair.dispose();
    });

    test('peer unavailable at start', () async {
      final pair = SyncPair();
      pair.phoneTransport.setPeerAvailable(false);
      await expectLater(
        pair.sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.peerUnavailable,
          ),
        ),
      );
      await pair.dispose();
    });

    test('peer never answers the handshake', () async {
      final pair = SyncPair();
      pair.phoneTransport.messageHook = (_) => ChunkFate.drop;
      await expectLater(
        pair.sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.peerUnavailable,
          ),
        ),
      );
      await pair.dispose();
    });

    test('a silent peer times out mid-session', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(
        phone: p,
        watch: w,
        options: const SyncOptions(
          retryInterval: Duration(milliseconds: 20),
          idleTimeout: Duration(milliseconds: 200),
        ),
      );
      var n = 0;
      pair.watchTransport.messageHook = (m) =>
          ++n > 1 ? ChunkFate.drop : ChunkFate.deliver; // only the hello-ack
      await expectLater(
        pair.sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.timeout,
          ),
        ),
      );
      await pair.dispose();
    });
  });

  group('handshake', () {
    test(
      'protocol version mismatch fails both sides with a clear error',
      () async {
        final (p, w) = await _populated();
        final pair = SyncPair(
          phone: p,
          watch: w,
          watchProtocolVersion: kSyncProtocolVersion + 1,
          watchMinProtocolVersion: kSyncProtocolVersion + 1,
        );
        final before = (p.dump(), w.dump());
        final watchSession = pair.watchEngine.incomingSessions.first;
        await expectLater(
          pair.sync(),
          throwsA(
            isA<SyncException>()
                .having((e) => e.code, 'code', SyncErrorCode.versionMismatch)
                .having(
                  (e) => e.peerVersion,
                  'peerVersion',
                  kSyncProtocolVersion + 1,
                )
                .having(
                  (e) => e.localVersion,
                  'localVersion',
                  kSyncProtocolVersion,
                ),
          ),
        );
        await expectLater(
          (await watchSession).result,
          throwsA(
            isA<SyncException>().having(
              (e) => e.code,
              'code',
              SyncErrorCode.versionMismatch,
            ),
          ),
        );
        expect(p.dump(), before.$1);
        expect(w.dump(), before.$2);
        await pair.dispose();
      },
    );

    test('a newer peer that still supports our version syncs fine', () async {
      final pair = SyncPair(
        watchProtocolVersion: kSyncProtocolVersion + 1,
        watchMinProtocolVersion: kSyncMinProtocolVersion,
      );
      await pair.phone.card('a', 3);
      await pair.sync();
      expect(pair.watch.dump().length, 1);
      await pair.dispose();
    });

    test('only the phone can initiate', () async {
      final pair = SyncPair();
      expect(() => pair.watchEngine.startSync(), throwsStateError);
      await pair.dispose();
    });
  });

  group('integrity', () {
    test('a transiently corrupted chunk is detected and re-fetched', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w, chunkSize: 2048);
      var corrupted = false;
      pair.phoneTransport.chunkHook = (c) {
        if (!corrupted && c.transferId.startsWith('cards:') && c.index == 2) {
          corrupted = true;
          c.bytes[0] ^= 0xFF;
        }
        return ChunkFate.deliver;
      };
      await pair.sync();
      expect(corrupted, isTrue);
      expect(p.dump(), w.dump());
      await pair.dispose();
    });

    test('a persistently corrupted chunk applies nothing anywhere', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w, chunkSize: 2048);
      pair.phoneTransport.chunkHook = (c) {
        if (c.transferId.startsWith('cards:') && c.index == 2) {
          c.bytes[0] ^= 0xFF;
        }
        return ChunkFate.deliver;
      };
      final before = (p.dump(), w.dump());
      final writes = (p.cards.writes, w.cards.writes);
      await expectLater(
        pair.sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.integrityFailure,
          ),
        ),
      );
      expect(p.dump(), before.$1);
      expect(w.dump(), before.$2);
      expect((p.cards.writes, w.cards.writes), writes);
      await pair.dispose();
    });
  });

  group('atomic apply', () {
    test('a store failure during commit rolls the watch back', () async {
      final (p, w) = await _populated();
      final pair = SyncPair(phone: p, watch: w);
      var puts = 0;
      w.cards.failOn = (op, id) {
        if (op == 'putCard' && ++puts == 10) throw StateError('disk full');
      };
      final before = (p.dump(), w.dump());
      await expectLater(
        pair.sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.storeFailure,
          ),
        ),
      );
      expect(w.dump(), before.$2);
      expect(p.dump(), before.$1);
      // After the fault clears, the sync completes and converges.
      w.cards.failOn = null;
      await pair.sync();
      expect(p.dump(), w.dump());
      expect(p.dump().length, 80);
      await pair.dispose();
    });

    test(
      'a local edit during the sync aborts it instead of clobbering',
      () async {
        final (p, w) = await _populated();
        final pair = SyncPair(phone: p, watch: w, chunkSize: 2048);
        var edited = false;
        pair.phoneTransport.chunkHook = (c) {
          if (!edited && c.transferId.startsWith('cards:')) {
            edited = true;
            w.cards.saveCard(
              CardSave(uid: '01', name: 'late', tag: TagType.mifare1K),
            );
          }
          return ChunkFate.deliver;
        };
        final phoneBefore = p.dump();
        await expectLater(
          pair.sync(),
          throwsA(
            isA<SyncException>().having(
              (e) => e.code,
              'code',
              SyncErrorCode.dataChanged,
            ),
          ),
        );
        expect(p.dump(), phoneBefore);
        expect(w.dump().length, 41); // 40 own + the late edit, nothing applied
        pair.phoneTransport.chunkHook = null;
        await pair.sync();
        expect(p.dump(), w.dump());
        await pair.dispose();
      },
    );
  });
}
