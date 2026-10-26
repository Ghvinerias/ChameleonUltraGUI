import 'dart:convert';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('legacy JSON (no updatedAt)', () {
    test('CardSave', () {
      final json = CardSave(
        id: 'c',
        uid: '01',
        name: 'n',
        tag: TagType.mifare1K,
      ).toJson();
      expect(jsonDecode(json).containsKey('updatedAt'), isFalse);
      expect(CardSave.fromJson(json).updatedAt, isNull);
    });

    test('CardFolder', () {
      final json = CardFolder(id: 'f', name: 'n').toJson();
      expect(jsonDecode(json).containsKey('updatedAt'), isFalse);
      expect(CardFolder.fromJson(json).updatedAt, isNull);
    });

    test('Dictionary', () {
      final json = Dictionary(id: 'd', name: 'n').toJson();
      expect(jsonDecode(json).containsKey('updatedAt'), isFalse);
      expect(Dictionary.fromJson(json).updatedAt, isNull);
    });

    test('DictionaryFolder', () {
      final json = DictionaryFolder(id: 'f', name: 'n').toJson();
      expect(jsonDecode(json).containsKey('updatedAt'), isFalse);
      expect(DictionaryFolder.fromJson(json).updatedAt, isNull);
    });
  });

  group('updatedAt round-trip', () {
    test('CardSave', () {
      final c = CardSave.fromJson(
        CardSave(
          id: 'c',
          uid: '01',
          name: 'n',
          tag: TagType.mifare1K,
          updatedAt: 123,
        ).toJson(),
      );
      expect(c.updatedAt, 123);
    });

    test('CardFolder', () {
      expect(
        CardFolder.fromJson(
          CardFolder(id: 'f', name: 'n', updatedAt: 5).toJson(),
        ).updatedAt,
        5,
      );
    });

    test('Dictionary', () {
      expect(
        Dictionary.fromJson(
          Dictionary(id: 'd', name: 'n', updatedAt: 7).toJson(),
        ).updatedAt,
        7,
      );
    });

    test('DictionaryFolder', () {
      expect(
        DictionaryFolder.fromJson(
          DictionaryFolder(id: 'f', name: 'n', updatedAt: 9).toJson(),
        ).updatedAt,
        9,
      );
    });

    test('bundles preserve updatedAt', () {
      final bundle = CardFolderBundle(
        rootFolderId: 'r',
        folders: [CardFolder(id: 'r', name: 'r', updatedAt: 1)],
        cards: [
          CardSave(
            id: 'c',
            uid: '01',
            name: 'n',
            tag: TagType.mifare1K,
            updatedAt: 2,
          ),
        ],
      );
      final decoded = CardFolderBundle.fromJson(bundle.toJson());
      expect(decoded.folders.single.updatedAt, 1);
      expect(decoded.cards.single.updatedAt, 2);

      final dbundle = DictionaryFolderBundle(
        rootFolderId: 'r',
        folders: [DictionaryFolder(id: 'r', name: 'r', updatedAt: 3)],
        dictionaries: [Dictionary(id: 'd', name: 'n', updatedAt: 4)],
      );
      final ddecoded = DictionaryFolderBundle.fromJson(dbundle.toJson());
      expect(ddecoded.folders.single.updatedAt, 3);
      expect(ddecoded.dictionaries.single.updatedAt, 4);
    });
  });

  group('SyncTombstone', () {
    test('round-trips every kind', () {
      for (final kind in SyncEntityKind.values) {
        final t = SyncTombstone(id: 'x', kind: kind, deletedAt: 42);
        expect(SyncTombstone.fromJson(t.toJson()), t);
      }
    });

    test('rejects unknown kind', () {
      expect(
        () => SyncTombstone.fromJson('{"id":"x","kind":"bogus","deletedAt":1}'),
        throwsFormatException,
      );
    });
  });
}
