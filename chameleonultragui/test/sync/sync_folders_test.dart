import 'dart:convert';

import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

Map<String, dynamic> _json(Replica r, String key) =>
    jsonDecode(r.dump()[key]!) as Map<String, dynamic>;

void main() {
  test(
    'folders are created before the items inside them (parents first)',
    () async {
      final pair = SyncPair();
      await pair.phone.cardFolder('child', 5, parent: 'root');
      await pair.phone.cardFolder('root', 5);
      await pair.phone.cardFolder('grand', 5, parent: 'child');
      await pair.phone.card('c1', 5, folder: 'grand');
      await pair.phone.card('c2', 5, folder: 'root');
      final seen = <String>[];
      pair.watch.cards.changes.listen(
        (c) => seen.add('${c.kind.name}:${c.id}'),
      );
      await pair.sync();
      await Future<void>.delayed(Duration.zero);
      int at(String s) => seen.indexOf(s);
      expect(seen.length, 5);
      expect(at('cardFolder:root'), lessThan(at('cardFolder:child')));
      expect(at('cardFolder:child'), lessThan(at('cardFolder:grand')));
      expect(at('cardFolder:grand'), lessThan(at('card:c1')));
      expect(at('cardFolder:root'), lessThan(at('card:c2')));
      expect(pair.phone.dump(), pair.watch.dump());
      await pair.dispose();
    },
  );

  test('sync-applied changes carry origin sync', () async {
    final pair = SyncPair();
    await pair.phone.card('c', 5);
    final origins = <StoreChangeOrigin>[];
    pair.watch.cards.changes.listen((c) => origins.add(c.origin));
    await pair.sync();
    await Future<void>.delayed(Duration.zero);
    expect(origins, [StoreChangeOrigin.sync]);
    await pair.dispose();
  });

  test(
    'deleting a folder with its contents removes the subtree on the watch',
    () async {
      final pair = SyncPair();
      await pair.phone.cardFolder('f', 1);
      await pair.phone.card('c', 1, folder: 'f');
      await pair.sync();
      expect(pair.watch.dump().length, 2);
      pair.phone.now = 50;
      await pair.phone.cards.deleteFolder('f', deleteContents: true);
      final r = await pair.sync();
      expect(pair.watch.dump(), isEmpty);
      expect(r.watch.of(SyncEntityKind.card).deleted, 1);
      expect(r.watch.of(SyncEntityKind.cardFolder).deleted, 1);
      expect(r.orphansMovedToRoot, 0);
      await pair.dispose();
    },
  );

  test(
    'orphan rule: an item left in a deleted folder moves to the root',
    () async {
      final pair = SyncPair();
      await pair.phone.cardFolder('f', 1);
      await pair.sync();
      // Phone deletes the folder; meanwhile the watch files a new card in it.
      pair.phone.now = 50;
      await pair.phone.cards.deleteFolder('f');
      pair.watch.now = 60;
      await pair.watch.cards.saveCard(
        CardSave(
          id: 'orphan',
          uid: '01',
          name: 'o',
          tag: TagType.mifare1K,
          folderId: 'f',
        ),
      );
      final r = await pair.sync();
      expect(pair.phone.dump(), pair.watch.dump());
      expect(pair.phone.dump().keys, ['card/orphan']);
      final card = _json(pair.phone, 'card/orphan');
      expect(card.containsKey('folderId'), isFalse);
      expect(card['updatedAt'], 60); // stamp untouched
      expect(r.orphansMovedToRoot, 1);
      expect((await pair.sync()).isNoOp, isTrue);
      await pair.dispose();
    },
  );

  test('orphan rule applies to items that were not transferred too', () async {
    final pair = SyncPair();
    await pair.phone.cardFolder('f', 1);
    await pair.phone.card('c', 1, folder: 'f');
    await pair.sync();
    // Folder deleted on the watch without touching the card (reparent=false
    // semantics are the store's business; here we only drop the folder).
    pair.watch.now = 70;
    await pair.watch.dead(SyncEntityKind.cardFolder, 'f', 70);
    final r = await pair.sync();
    expect(pair.phone.dump(), pair.watch.dump());
    expect(_json(pair.phone, 'card/c').containsKey('folderId'), isFalse);
    expect(pair.phone.dump().containsKey('folder/f'), isFalse);
    expect(r.orphansMovedToRoot, 1);
    await pair.dispose();
  });

  test('child folder of a deleted parent moves to the root', () async {
    final pair = SyncPair();
    await pair.phone.cardFolder('p', 1);
    await pair.phone.cardFolder('k', 1, parent: 'p');
    await pair.sync();
    await pair.phone.dead(SyncEntityKind.cardFolder, 'p', 9);
    await pair.sync();
    expect(pair.watch.dump().keys, ['folder/k']);
    expect(_json(pair.watch, 'folder/k').containsKey('parentId'), isFalse);
    expect(pair.phone.dump(), pair.watch.dump());
    await pair.dispose();
  });

  test(
    'a folder cycle created on two replicas is broken at the smallest id',
    () async {
      final pair = SyncPair();
      await pair.phone.cardFolder('a', 1);
      await pair.phone.cardFolder('b', 1);
      await pair.sync();
      await pair.phone.cardFolder('a', 10, parent: 'b'); // a under b
      await pair.watch.cardFolder('b', 11, parent: 'a'); // b under a
      final r = await pair.sync();
      expect(pair.phone.dump(), pair.watch.dump());
      expect(_json(pair.phone, 'folder/a').containsKey('parentId'), isFalse);
      expect(_json(pair.phone, 'folder/b')['parentId'], 'a');
      expect(r.orphansMovedToRoot, 1);
      expect((await pair.sync()).isNoOp, isTrue);
      await pair.dispose();
    },
  );

  test('dictionary folders follow the same rules', () async {
    final pair = SyncPair();
    await pair.phone.dictFolder('df', 1);
    await pair.phone.dict('d', 1, folder: 'df');
    await pair.sync();
    await pair.watch.dead(SyncEntityKind.dictionaryFolder, 'df', 20);
    await pair.sync();
    expect(pair.phone.dump(), pair.watch.dump());
    expect(_json(pair.phone, 'dict/d').containsKey('folderId'), isFalse);
    await pair.dispose();
  });
}
