import 'dart:async';

import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';

/// In-memory [CardStore] honouring the documented sync rules. Entities are
/// kept as JSON so callers never share mutable instances (like the prefs
/// store).
class InMemoryCardStore implements CardStore {
  int Function() clock;

  /// Test hook: called before every `*FromSync` write; throw to simulate a
  /// storage failure.
  void Function(String op, String id)? failOn;

  final Map<String, String> _cards = {};
  final Map<String, String> _folders = {};
  final Map<String, SyncTombstone> _tombstones = {};
  final _changes = StreamController<StoreChange>.broadcast();

  /// Number of store write calls (any kind), for "nothing was touched".
  int writes = 0;

  InMemoryCardStore({int Function()? clock})
    : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  void _emit(SyncEntityKind k, String id, StoreChangeType t, bool sync) =>
      _changes.add(
        StoreChange(
          kind: k,
          id: id,
          type: t,
          origin: sync ? StoreChangeOrigin.sync : StoreChangeOrigin.local,
        ),
      );

  void _tombstone(SyncEntityKind k, String id) {
    _tombstones['${k.name}/$id'] = SyncTombstone(
      id: id,
      kind: k,
      deletedAt: clock(),
    );
  }

  @override
  Future<List<CardSave>> getCards() async =>
      _cards.values.map(CardSave.fromJson).toList();

  @override
  Future<CardSave?> getCard(String id) async =>
      _cards[id] == null ? null : CardSave.fromJson(_cards[id]!);

  @override
  Future<CardSave> saveCard(CardSave card) async {
    writes++;
    final existed = _cards.containsKey(card.id);
    card.updatedAt = clock();
    _cards[card.id] = card.toJson();
    _tombstones.remove('${SyncEntityKind.card.name}/${card.id}');
    _emit(
      SyncEntityKind.card,
      card.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      false,
    );
    return CardSave.fromJson(_cards[card.id]!);
  }

  @override
  Future<void> deleteCard(String id) async {
    if (_cards.remove(id) == null) return;
    writes++;
    _tombstone(SyncEntityKind.card, id);
    _emit(SyncEntityKind.card, id, StoreChangeType.deleted, false);
  }

  @override
  Future<List<CardFolder>> getFolders() async =>
      _folders.values.map(CardFolder.fromJson).toList();

  @override
  Future<CardFolder> saveFolder(CardFolder folder) async {
    writes++;
    final existed = _folders.containsKey(folder.id);
    folder.updatedAt = clock();
    _folders[folder.id] = folder.toJson();
    _tombstones.remove('${SyncEntityKind.cardFolder.name}/${folder.id}');
    _emit(
      SyncEntityKind.cardFolder,
      folder.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      false,
    );
    return CardFolder.fromJson(_folders[folder.id]!);
  }

  @override
  Future<void> deleteFolder(String id, {bool deleteContents = true}) async {
    final folder = _folders[id];
    if (folder == null) return;
    final parent = CardFolder.fromJson(folder).parentId;
    final childFolders = (await getFolders())
        .where((f) => f.parentId == id)
        .toList();
    final cards = (await getCards()).where((c) => c.folderId == id).toList();
    if (deleteContents) {
      for (final f in childFolders) {
        await deleteFolder(f.id);
      }
      for (final c in cards) {
        await deleteCard(c.id);
      }
    } else {
      for (final f in childFolders) {
        f.parentId = parent;
        await saveFolder(f);
      }
      for (final c in cards) {
        c.folderId = parent;
        await saveCard(c);
      }
    }
    _folders.remove(id);
    writes++;
    _tombstone(SyncEntityKind.cardFolder, id);
    _emit(SyncEntityKind.cardFolder, id, StoreChangeType.deleted, false);
  }

  @override
  Future<List<SyncTombstone>> getTombstones() async =>
      _tombstones.values.toList();

  @override
  Future<void> pruneTombstones(int olderThanMs) async {
    _tombstones.removeWhere((_, t) => t.deletedAt < olderThanMs);
  }

  @override
  Future<void> putCardFromSync(CardSave card) async {
    failOn?.call('putCard', card.id);
    writes++;
    final existed = _cards.containsKey(card.id);
    _cards[card.id] = card.toJson();
    _tombstones.remove('${SyncEntityKind.card.name}/${card.id}');
    _emit(
      SyncEntityKind.card,
      card.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      true,
    );
  }

  @override
  Future<void> putFolderFromSync(CardFolder folder) async {
    failOn?.call('putFolder', folder.id);
    writes++;
    final existed = _folders.containsKey(folder.id);
    _folders[folder.id] = folder.toJson();
    _tombstones.remove('${SyncEntityKind.cardFolder.name}/${folder.id}');
    _emit(
      SyncEntityKind.cardFolder,
      folder.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      true,
    );
  }

  /// Verbatim: removes exactly one entity (no cascade) and records exactly
  /// the supplied tombstone.
  @override
  Future<void> deleteFromSync(SyncTombstone t) async {
    failOn?.call('delete', t.id);
    writes++;
    final removed = t.kind == SyncEntityKind.cardFolder
        ? _folders.remove(t.id)
        : _cards.remove(t.id);
    _tombstones['${t.kind.name}/${t.id}'] = t;
    if (removed != null) _emit(t.kind, t.id, StoreChangeType.deleted, true);
  }

  @override
  Stream<StoreChange> get changes => _changes.stream;

  /// Canonical dump for equality assertions (sorted JSON by id).
  Map<String, String> dump() => {
    for (final k in _cards.keys.toList()..sort()) 'card/$k': _cards[k]!,
    for (final k in _folders.keys.toList()..sort()) 'folder/$k': _folders[k]!,
  };
}
