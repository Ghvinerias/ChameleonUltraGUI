import 'package:chameleonultragui/core/stores/prefs_card_store.dart';
import 'package:chameleonultragui/core/stores/prefs_dictionary_store.dart';
import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CardSave card(String id, {String? folderId, String name = 'c'}) => CardSave(
  id: id,
  uid: '01',
  name: name,
  tag: TagType.mifare1K,
  folderId: folderId,
);

void main() {
  late SharedPreferences prefs;
  late int now;
  late PrefsCardStore cards;
  late PrefsDictionaryStore dicts;
  late List<StoreChange> events;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = 1000;
    cards = PrefsCardStore(prefs, clock: () => now);
    dicts = PrefsDictionaryStore(prefs, clock: () => now);
    events = [];
    cards.changes.listen(events.add);
    dicts.changes.listen(events.add);
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('CardStore', () {
    test('save stamps updatedAt, overwriting caller value', () async {
      final saved = await cards.saveCard(card('a')..updatedAt = 5);
      expect(saved.updatedAt, 1000);
      now = 2000;
      final again = await cards.saveCard(card('a', name: 'x'));
      expect(again.updatedAt, 2000);
      expect((await cards.getCards()).single.name, 'x');
      await flush();
      expect(events.map((e) => e.type),
          [StoreChangeType.created, StoreChangeType.updated]);
      expect(events.every((e) => e.origin == StoreChangeOrigin.local), isTrue);
    });

    test('delete records tombstone; missing id is a no-op', () async {
      await cards.saveCard(card('a'));
      now = 3000;
      await cards.deleteCard('a');
      await cards.deleteCard('nope');
      expect(await cards.getCards(), isEmpty);
      expect(await cards.getTombstones(), [
        const SyncTombstone(
            id: 'a', kind: SyncEntityKind.card, deletedAt: 3000),
      ]);
      await flush();
      expect(events.last.type, StoreChangeType.deleted);
      expect(events.length, 2);
    });

    test('re-creating with same id clears tombstone', () async {
      await cards.saveCard(card('a'));
      await cards.deleteCard('a');
      expect(await cards.getTombstones(), hasLength(1));
      await cards.saveCard(card('a'));
      expect(await cards.getTombstones(), isEmpty);
    });

    test('deleteFolder cascades with tombstones', () async {
      await cards.saveFolder(CardFolder(id: 'f1', name: 'one'));
      await cards.saveFolder(CardFolder(id: 'f2', name: 'two', parentId: 'f1'));
      await cards.saveFolder(CardFolder(id: 'keep', name: 'keep'));
      await cards.saveCard(card('a', folderId: 'f1'));
      await cards.saveCard(card('b', folderId: 'f2'));
      await cards.saveCard(card('c', folderId: 'keep'));
      now = 5000;
      await cards.deleteFolder('f1');
      expect((await cards.getCards()).map((c) => c.id), ['c']);
      expect((await cards.getFolders()).map((f) => f.id), ['keep']);
      final ids = (await cards.getTombstones()).map((t) => t.id).toSet();
      expect(ids, {'f1', 'f2', 'a', 'b'});
    });

    test('deleteFolder(deleteContents:false) re-parents and stamps', () async {
      await cards.saveFolder(CardFolder(id: 'root', name: 'r'));
      await cards.saveFolder(CardFolder(id: 'f', name: 'f', parentId: 'root'));
      await cards.saveCard(card('a', folderId: 'f'));
      now = 7000;
      await cards.deleteFolder('f', deleteContents: false);
      final a = (await cards.getCard('a'))!;
      expect(a.folderId, 'root');
      expect(a.updatedAt, 7000);
      expect((await cards.getTombstones()).map((t) => t.id), ['f']);
    });

    test('FromSync is verbatim and tagged sync', () async {
      await cards.putCardFromSync(card('a')..updatedAt = 42);
      expect((await cards.getCard('a'))!.updatedAt, 42);
      await cards.deleteFromSync(const SyncTombstone(
          id: 'a', kind: SyncEntityKind.card, deletedAt: 99));
      expect(await cards.getCards(), isEmpty);
      expect(await cards.getTombstones(), [
        const SyncTombstone(
            id: 'a', kind: SyncEntityKind.card, deletedAt: 99),
      ]);
      // remote tombstone for something we never had is still recorded
      await cards.deleteFromSync(const SyncTombstone(
          id: 'z', kind: SyncEntityKind.cardFolder, deletedAt: 10));
      expect(await cards.getTombstones(), hasLength(2));
      // a newer remote entity clears the tombstone, keeping its stamp
      await cards.putCardFromSync(card('a')..updatedAt = 100);
      expect((await cards.getTombstones()).map((t) => t.id), ['z']);
      await flush();
      expect(events.every((e) => e.origin == StoreChangeOrigin.sync), isTrue);
      expect(events.map((e) => e.type), [
        StoreChangeType.created,
        StoreChangeType.deleted,
        StoreChangeType.deleted,
        StoreChangeType.created,
      ]);
    });

    test('tombstone merge keeps the newest deletedAt', () async {
      await cards.deleteFromSync(const SyncTombstone(
          id: 'a', kind: SyncEntityKind.card, deletedAt: 50));
      await cards.deleteFromSync(const SyncTombstone(
          id: 'a', kind: SyncEntityKind.card, deletedAt: 20));
      expect((await cards.getTombstones()).single.deletedAt, 50);
    });

    test('pruneTombstones and retention pruning', () async {
      await cards.deleteFromSync(const SyncTombstone(
          id: 'old', kind: SyncEntityKind.card, deletedAt: 10));
      await cards.deleteFromSync(const SyncTombstone(
          id: 'new', kind: SyncEntityKind.card, deletedAt: 500));
      await cards.pruneTombstones(100);
      expect((await cards.getTombstones()).map((t) => t.id), ['new']);

      final day = const Duration(days: 1).inMilliseconds;
      final store = PrefsCardStore(prefs,
          clock: () => 100 * day, retention: const Duration(days: 90));
      await store.deleteFromSync(SyncTombstone(
          id: 'ancient', kind: SyncEntityKind.card, deletedAt: 5 * day));
      await store.deleteFromSync(SyncTombstone(
          id: 'recent', kind: SyncEntityKind.card, deletedAt: 50 * day));
      store.pruneExpired();
      expect((await store.getTombstones()).map((t) => t.id), ['recent']);
    });

    test('bulk replace diffs: stamps only changed, tombstones removed',
        () async {
      await cards.saveCard(card('keep'));
      await cards.saveCard(card('edit'));
      await cards.saveCard(card('gone'));
      now = 9000;
      final list = await cards.getCards();
      final next = [
        list[0],
        list[1]..name = 'renamed',
        card('fresh'),
      ];
      events.clear();
      cards.replaceCards(next);
      final out = {for (final c in await cards.getCards()) c.id: c};
      expect(out['keep']!.updatedAt, 1000);
      expect(out['edit']!.updatedAt, 9000);
      expect(out['fresh']!.updatedAt, 9000);
      expect(out.containsKey('gone'), isFalse);
      expect((await cards.getTombstones()).single.id, 'gone');
      await flush();
      expect(events.map((e) => '${e.id}:${e.type.name}').toSet(),
          {'edit:updated', 'fresh:created', 'gone:deleted'});
    });
  });

  group('DictionaryStore', () {
    test('save, key length filter, system dictionary ignored', () async {
      await dicts.saveDictionary(Dictionary(id: 'a', name: 'a', keyLength: 12));
      await dicts.saveDictionary(Dictionary(id: 'b', name: 'b', keyLength: 8));
      final ignored = await dicts.saveDictionary(Dictionary(id: ''));
      expect(ignored.updatedAt, isNull);
      expect((await dicts.getDictionaries()).length, 2);
      expect(
          (await dicts.getDictionaries(keyLength: 8)).map((d) => d.id), ['b']);
      expect((await dicts.getDictionary('a'))!.updatedAt, 1000);
    });

    test('delete + folder cascade + FromSync', () async {
      await dicts.saveFolder(DictionaryFolder(id: 'f', name: 'f'));
      await dicts.saveDictionary(
          Dictionary(id: 'a', name: 'a', keyLength: 12, folderId: 'f'));
      await dicts.saveDictionary(Dictionary(id: 'b', name: 'b', keyLength: 12));
      now = 4000;
      await dicts.deleteFolder('f');
      await dicts.deleteDictionary('b');
      expect(await dicts.getDictionaries(), isEmpty);
      expect((await dicts.getTombstones()).map((t) => t.kind).toSet(), {
        SyncEntityKind.dictionary,
        SyncEntityKind.dictionaryFolder,
      });
      await dicts.putDictionaryFromSync(
          Dictionary(id: 'a', name: 'a', keyLength: 12)..updatedAt = 77);
      expect((await dicts.getDictionary('a'))!.updatedAt, 77);
      expect((await dicts.getTombstones()).map((t) => t.id).toSet(),
          {'f', 'b'});
    });

    test('bulk replace diffs and never persists id ""', () async {
      await dicts.saveDictionary(Dictionary(id: 'a', name: 'a', keyLength: 12));
      now = 8000;
      dicts.replaceDictionaries([Dictionary(id: ''), Dictionary(id: 'n')]);
      expect((await dicts.getDictionaries()).map((d) => d.id), ['n']);
      expect((await dicts.getTombstones()).single.id, 'a');
    });
  });

  group('SharedPreferencesProvider call path', () {
    test('deleting a card via legacy setCards leaves a persisted tombstone',
        () async {
      SharedPreferences.setMockInitialValues({});
      final p = SharedPreferencesProvider();
      await p.load();
      p.setCards([card('a'), card('b')]);
      expect(p.getCards().every((c) => c.updatedAt != null), isTrue);
      // the same shape as the UI delete: filter the list and save it
      p.setCards(p.getCards().where((c) => c.id != 'a').toList());
      expect(p.getCards().map((c) => c.id), ['b']);
      // survives a reload (tombstone persisted in SharedPreferences)
      await p.load();
      final t = await p.cardStore.getTombstones();
      expect(t.single.id, 'a');
      expect(t.single.kind, SyncEntityKind.card);
    });

    test('load() prunes expired tombstones', () async {
      final old = const SyncTombstone(
          id: 'x', kind: SyncEntityKind.card, deletedAt: 1);
      SharedPreferences.setMockInitialValues({
        'card_tombstones': [old.toJson()],
      });
      final p = SharedPreferencesProvider();
      await p.load();
      expect(await p.cardStore.getTombstones(), isEmpty);
    });
  });
}
