import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

void main() {
  test('first sync copies both ways and is then a no-op', () async {
    final pair = SyncPair();
    await pair.phone.card('p1', 10);
    await pair.phone.cardFolder('f1', 10);
    await pair.watch.card('w1', 20);
    await pair.watch.dict('d1', 5);
    final r = await pair.sync();
    expect(r.watch.of(SyncEntityKind.card).added, 1);
    expect(r.phone.of(SyncEntityKind.card).added, 1);
    expect(r.watch.of(SyncEntityKind.cardFolder).added, 1);
    expect(r.phone.of(SyncEntityKind.dictionary).added, 1);
    expect(pair.phone.dump(), pair.watch.dump());
    expect(pair.phone.dump().length, 4);
    final r2 = await pair.sync();
    expect(r2.isNoOp, isTrue);
    await pair.dispose();
  });
}
