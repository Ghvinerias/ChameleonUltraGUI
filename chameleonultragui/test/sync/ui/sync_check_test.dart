import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/ui/sync_check.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/in_memory_sync_transport.dart';

void main() {
  late InMemorySyncTransport phone;
  late InMemorySyncTransport watch;
  late SyncCheck a;
  late SyncCheck b;

  setUp(() {
    final (p, w) = InMemorySyncTransport.pair();
    phone = p;
    watch = w;
    a = SyncCheck(
      transport: SyncTransportSplit(phone).checkView,
      transferTimeout: const Duration(milliseconds: 500),
      pingTimeout: const Duration(milliseconds: 300),
    );
    b = SyncCheck(
      transport: SyncTransportSplit(watch).checkView,
      transferTimeout: const Duration(milliseconds: 500),
      pingTimeout: const Duration(milliseconds: 300),
    )..startResponder();
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('passes with 1 MB each way and reports throughput', () async {
    final r = await a.run();
    expect(r.passed, isTrue);
    expect(r.pingSamples, 3);
    expect(r.send.bytes, 1024 * 1024);
    expect(r.receive.bytes, 1024 * 1024);
    expect(r.send.bytesPerSecond, greaterThan(0));
    expect(r.receive.bytesPerSecond, greaterThan(0));
  });

  test('a corrupted chunk fails the direction it travelled', () async {
    phone.chunkHook = (c) {
      c.bytes[0] ^= 0xff;
      return ChunkFate.deliver;
    };
    final r = await a.run();
    expect(r.passed, isFalse);
    expect(r.pingOk, isTrue);
    expect(r.send.ok, isFalse);
    expect(r.send.error, contains('integrity'));
    expect(r.receive.ok, isTrue);
  });

  test('corruption on the way back fails the receive direction', () async {
    watch.chunkHook = (c) {
      c.bytes[10] ^= 0x01;
      return ChunkFate.deliver;
    };
    final r = await a.run();
    expect(r.send.ok, isTrue);
    expect(r.receive.ok, isFalse);
    expect(r.receive.error, contains('integrity'));
  });

  test('a dropped chunk is reported as missing', () async {
    phone.chunkHook = (c) => c.index == 3 ? ChunkFate.drop : ChunkFate.deliver;
    final r = await a.run();
    expect(r.send.ok, isFalse);
    expect(r.send.error, contains('missing 1 of'));
  });

  test('no responder: ping fails and transfers are skipped', () async {
    await b.dispose();
    final r = await a.run();
    expect(r.pingOk, isFalse);
    expect(r.send.skipped, isTrue);
    expect(r.receive.skipped, isTrue);
    expect(r.passed, isFalse);
  });

  test('peer unavailable is reported, not thrown', () async {
    phone.setPeerAvailable(false);
    final r = await a.run();
    expect(r.passed, isFalse);
    expect(r.pingError, isNotNull);
  });

  test('split keeps check traffic away from the engine view', () async {
    final split = SyncTransportSplit(watch);
    final engineMsgs = <SyncMessage>[];
    split.engineView.messages.listen(engineMsgs.add);
    await a.run();
    expect(engineMsgs, isEmpty);
  });
}
