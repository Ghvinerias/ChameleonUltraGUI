// Characterization of SharedPreferencesProvider card/dictionary/folder
// persistence. Must pass both before and after the T7 store refactor
// (stamping only adds `updatedAt`, which these tests never compare).
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dictionary dict(String id, int keyLength, {String? folderId}) => Dictionary(
  id: id,
  name: 'dict $id',
  keyLength: keyLength,
  folderId: folderId,
  keys: [Uint8List.fromList(List.filled(keyLength ~/ 2, 0xAB))],
);

CardSave card(String id, {String? folderId}) => CardSave(
  id: id,
  uid: '01020304',
  name: 'card $id',
  tag: TagType.mifare1K,
  folderId: folderId,
);

Future<SharedPreferencesProvider> freshProvider([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final p = SharedPreferencesProvider();
  await p.load();
  return p;
}

void main() {
  test('cards round trip', () async {
    final p = await freshProvider();
    expect(p.getCards(), isEmpty);
    p.setCards([card('a'), card('b', folderId: 'f')]);
    final cards = p.getCards();
    expect(cards.map((c) => c.id), ['a', 'b']);
    expect(cards[1].folderId, 'f');
    expect(cards[0].name, 'card a');
    expect(cards[0].tag, TagType.mifare1K);
  });

  test('cards: removal and reorder are persisted', () async {
    final p = await freshProvider();
    p.setCards([card('a'), card('b'), card('c')]);
    p.setCards([card('c'), card('a')]);
    expect(p.getCards().map((c) => c.id), ['c', 'a']);
    p.setCards([]);
    expect(p.getCards(), isEmpty);
  });

  test('legacy JSON without new fields loads', () async {
    final legacyCard = jsonEncode({
      'id': 'lc',
      'uid': '01',
      'sak': 8,
      'atqa': [4, 0],
      'name': 'legacy',
      'tag': TagType.mifare1K.value,
      'data': [],
    });
    final legacyDict = jsonEncode({
      'id': 'ld',
      'name': 'legacy dict',
      'keys': [
        [1, 2, 3, 4, 5, 6],
      ],
    });
    final legacyFolder = jsonEncode({'id': 'lf', 'name': 'folder'});
    final p = await freshProvider({
      'cards': [legacyCard],
      'dictionaries': [legacyDict],
      'card_folders': [legacyFolder],
      'dictionary_folders': [legacyFolder],
    });
    expect(p.getCards().single.updatedAt, isNull);
    expect(p.getCards().single.folderId, isNull);
    final d = p.getDictionaries().single;
    expect(d.keyLength, 12);
    expect(d.updatedAt, isNull);
    expect(p.getCardFolders().single.parentId, isNull);
    expect(p.getDictionaryFolders().single.name, 'folder');
  });

  test('dictionaries round trip and system empty dictionary skipped', () async {
    final p = await freshProvider();
    p.setDictionaries([dict('a', 12), Dictionary(id: '', name: 'empty')]);
    final out = p.getDictionaries();
    expect(out.map((d) => d.id), ['a']);
    expect(out.single.keys.single, Uint8List.fromList(List.filled(6, 0xAB)));
  });

  test('getDictionaries(keyLength) filters', () async {
    final p = await freshProvider();
    p.setDictionaries([dict('a', 12), dict('b', 8), dict('c', 12)]);
    expect(p.getDictionaries().length, 3);
    expect(p.getDictionaries(keyLength: 12).map((d) => d.id), ['a', 'c']);
    expect(p.getDictionaries(keyLength: 8).map((d) => d.id), ['b']);
    expect(p.getDictionaries(keyLength: 32), isEmpty);
  });

  test('folders round trip and moves', () async {
    final p = await freshProvider();
    p.setCardFolders([
      CardFolder(id: 'f1', name: 'one'),
      CardFolder(id: 'f2', name: 'two', parentId: 'f1'),
    ]);
    p.setCards([card('a', folderId: 'f1')]);
    var folders = p.getCardFolders();
    expect(folders[1].parentId, 'f1');
    // move card and folder
    final cards = p.getCards();
    cards[0].folderId = 'f2';
    p.setCards(cards);
    expect(p.getCards().single.folderId, 'f2');
    folders[1].parentId = null;
    p.setCardFolders(folders);
    expect(p.getCardFolders()[1].parentId, isNull);

    p.setDictionaryFolders([DictionaryFolder(id: 'd1', name: 'x')]);
    p.setDictionaries([dict('a', 12, folderId: 'd1')]);
    expect(p.getDictionaryFolders().single.id, 'd1');
    expect(p.getDictionaries().single.folderId, 'd1');
  });
}
