import 'dart:math';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/in_memory_sync_transport.dart';
import 'sync_harness.dart';

Future<void> _bigCard(Replica r, String id, int blocks, int seed) async {
  final rnd = Random(seed);
  await r.cards.putCardFromSync(
    CardSave(
      id: id,
      uid: '04AABBCCDD',
      name: id,
      tag: TagType.mifare4K,
      updatedAt: 7,
      data: [
        for (var b = 0; b < blocks; b++)
          Uint8List.fromList([for (var k = 0; k < 4096; k++) rnd.nextInt(256)]),
      ],
    ),
  );
}

void main() {
  test('a ~5 MB bundle round-trips in both directions', () async {
    final pair = SyncPair(chunkSize: 32 * 1024);
    // ~1.4 MB of raw bytes serialise to about 5 MB of JSON.
    await _bigCard(pair.phone, 'big-phone', 370, 1);
    await _bigCard(pair.watch, 'big-watch', 370, 2);
    final size = pair.phone.dump()['card/big-phone']!.length;
    expect(size, greaterThan(4800 * 1024));

    final events = <double>[];
    final session = pair.phoneEngine.startSync();
    session.events.listen((e) {
      if (e.runtimeType.toString() == 'SyncProgressEvent') {
        events.add((e as dynamic).fraction as double);
      }
    });
    final report = await session.result.timeout(const Duration(seconds: 60));
    expect(pair.phone.dump(), pair.watch.dump());
    expect(pair.watch.dump()['card/big-phone'], isNotNull);
    expect(report.bytesSent, greaterThan(size));
    expect(report.bytesReceived, greaterThan(size));
    expect(events, isNotEmpty);
    expect(events.last, closeTo(1, 1e-9));
    expect((await pair.sync()).isNoOp, isTrue);
    await pair.dispose();
  });

  test('a 5 MB bundle survives a lossy link', () async {
    final pair = SyncPair(chunkSize: 32 * 1024);
    await _bigCard(pair.phone, 'big', 370, 3);
    final rnd = Random(5);
    pair.phoneTransport.chunkHook = (_) =>
        rnd.nextDouble() < 0.2 ? ChunkFate.drop : ChunkFate.deliver;
    await pair.sync();
    expect(pair.phone.dump(), pair.watch.dump());
    await pair.dispose();
  });
}
