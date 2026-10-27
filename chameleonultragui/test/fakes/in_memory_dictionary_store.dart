import 'dart:async';

import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';

/// In-memory [DictionaryStore]; see `InMemoryCardStore`.
class InMemoryDictionaryStore implements DictionaryStore {
  int Function() clock;
  void Function(String op, String id)? failOn;

  final Map<String, String> _dicts = {};
  final Map<String, String> _folders = {};
  final Map<String, SyncTombstone> _tombstones = {};
  final _changes = StreamController<StoreChange>.broadcast();
  int writes = 0;

  InMemoryDictionaryStore({int Function()? clock})
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
  Future<List<Dictionary>> getDictionaries({int keyLength = 0}) async => _dicts
      .values
      .map(Dictionary.fromJson)
      .where((d) => keyLength == 0 || d.keyLength == keyLength)
      .toList();

  @override
  Future<Dictionary?> getDictionary(String id) async =>
      _dicts[id] == null ? null : Dictionary.fromJson(_dicts[id]!);

  @override
  Future<Dictionary> saveDictionary(Dictionary dictionary) async {
    if (dictionary.id.isEmpty) return dictionary;
    writes++;
    final existed = _dicts.containsKey(dictionary.id);
    dictionary.updatedAt = clock();
    _dicts[dictionary.id] = dictionary.toJson();
    _tombstones.remove('${SyncEntityKind.dictionary.name}/${dictionary.id}');
    _emit(
      SyncEntityKind.dictionary,
      dictionary.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      false,
    );
    return Dictionary.fromJson(_dicts[dictionary.id]!);
  }

  @override
  Future<void> deleteDictionary(String id) async {
    if (_dicts.remove(id) == null) return;
    writes++;
    _tombstone(SyncEntityKind.dictionary, id);
    _emit(SyncEntityKind.dictionary, id, StoreChangeType.deleted, false);
  }

  @override
  Future<List<DictionaryFolder>> getFolders() async =>
      _folders.values.map(DictionaryFolder.fromJson).toList();

  @override
  Future<DictionaryFolder> saveFolder(DictionaryFolder folder) async {
    writes++;
    final existed = _folders.containsKey(folder.id);
    folder.updatedAt = clock();
    _folders[folder.id] = folder.toJson();
    _tombstones.remove('${SyncEntityKind.dictionaryFolder.name}/${folder.id}');
    _emit(
      SyncEntityKind.dictionaryFolder,
      folder.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      false,
    );
    return DictionaryFolder.fromJson(_folders[folder.id]!);
  }

  @override
  Future<void> deleteFolder(String id, {bool deleteContents = true}) async {
    final folder = _folders[id];
    if (folder == null) return;
    final parent = DictionaryFolder.fromJson(folder).parentId;
    final childFolders = (await getFolders())
        .where((f) => f.parentId == id)
        .toList();
    final dicts = (await getDictionaries())
        .where((d) => d.folderId == id)
        .toList();
    if (deleteContents) {
      for (final f in childFolders) {
        await deleteFolder(f.id);
      }
      for (final d in dicts) {
        await deleteDictionary(d.id);
      }
    } else {
      for (final f in childFolders) {
        f.parentId = parent;
        await saveFolder(f);
      }
      for (final d in dicts) {
        d.folderId = parent;
        await saveDictionary(d);
      }
    }
    _folders.remove(id);
    writes++;
    _tombstone(SyncEntityKind.dictionaryFolder, id);
    _emit(SyncEntityKind.dictionaryFolder, id, StoreChangeType.deleted, false);
  }

  @override
  Future<List<SyncTombstone>> getTombstones() async =>
      _tombstones.values.toList();

  @override
  Future<void> pruneTombstones(int olderThanMs) async {
    _tombstones.removeWhere((_, t) => t.deletedAt < olderThanMs);
  }

  @override
  Future<void> putDictionaryFromSync(Dictionary dictionary) async {
    failOn?.call('putDictionary', dictionary.id);
    writes++;
    final existed = _dicts.containsKey(dictionary.id);
    _dicts[dictionary.id] = dictionary.toJson();
    _tombstones.remove('${SyncEntityKind.dictionary.name}/${dictionary.id}');
    _emit(
      SyncEntityKind.dictionary,
      dictionary.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      true,
    );
  }

  @override
  Future<void> putFolderFromSync(DictionaryFolder folder) async {
    failOn?.call('putFolder', folder.id);
    writes++;
    final existed = _folders.containsKey(folder.id);
    _folders[folder.id] = folder.toJson();
    _tombstones.remove('${SyncEntityKind.dictionaryFolder.name}/${folder.id}');
    _emit(
      SyncEntityKind.dictionaryFolder,
      folder.id,
      existed ? StoreChangeType.updated : StoreChangeType.created,
      true,
    );
  }

  @override
  Future<void> deleteFromSync(SyncTombstone t) async {
    failOn?.call('delete', t.id);
    writes++;
    final removed = t.kind == SyncEntityKind.dictionaryFolder
        ? _folders.remove(t.id)
        : _dicts.remove(t.id);
    _tombstones['${t.kind.name}/${t.id}'] = t;
    if (removed != null) _emit(t.kind, t.id, StoreChangeType.deleted, true);
  }

  @override
  Stream<StoreChange> get changes => _changes.stream;

  Map<String, String> dump() => {
    for (final k in _dicts.keys.toList()..sort()) 'dict/$k': _dicts[k]!,
    for (final k in _folders.keys.toList()..sort()) 'folder/$k': _folders[k]!,
  };
}
