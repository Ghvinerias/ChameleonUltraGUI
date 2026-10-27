// SharedPreferences-backed [DictionaryStore] (Track T7).
//
// Storage keys: `dictionaries`, `dictionary_folders` (unchanged, legacy
// compatible) and `dictionary_tombstones` (new). See `PrefsCardStore`.
import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/core/stores/prefs_collection.dart';
import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsDictionaryStore implements DictionaryStore {
  final Duration retention;
  final int Function() _clock;
  final StoreChangeBus _bus = StoreChangeBus();
  late final TombstoneLog _tombstones;
  late final PrefsCollection<Dictionary> _dictionaries;
  late final PrefsCollection<DictionaryFolder> _folders;

  PrefsDictionaryStore(
    SharedPreferences prefs, {
    int Function()? clock,
    this.retention = kDefaultTombstoneRetention,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _tombstones = TombstoneLog(prefs, 'dictionary_tombstones');
    _dictionaries = PrefsCollection<Dictionary>(
      prefs: prefs,
      key: 'dictionaries',
      kind: SyncEntityKind.dictionary,
      tombstones: _tombstones,
      idOf: (d) => d.id,
      updatedAtOf: (d) => d.updatedAt,
      setUpdatedAt: (d, v) => d.updatedAt = v,
      toJson: (d) => d.toJson(),
      fromJson: Dictionary.fromJson,
      clock: _clock,
      emit: _bus.add,
    );
    _folders = PrefsCollection<DictionaryFolder>(
      prefs: prefs,
      key: 'dictionary_folders',
      kind: SyncEntityKind.dictionaryFolder,
      tombstones: _tombstones,
      idOf: (f) => f.id,
      updatedAtOf: (f) => f.updatedAt,
      setUpdatedAt: (f, v) => f.updatedAt = v,
      toJson: (f) => f.toJson(),
      fromJson: DictionaryFolder.fromJson,
      clock: _clock,
      emit: _bus.add,
    );
  }

  /// Drops tombstones older than [retention].
  void pruneExpired() => _tombstones
      .prune(_clock() - retention.inMilliseconds);

  // Synchronous API used by the legacy SharedPreferencesProvider setters.
  List<Dictionary> getDictionariesSync({int keyLength = 0}) => _dictionaries
      .list()
      .where((d) => keyLength == 0 || d.keyLength == keyLength)
      .toList();
  List<DictionaryFolder> getFoldersSync() => _folders.list();

  /// The system empty dictionary (id "") is never persisted.
  void replaceDictionaries(List<Dictionary> dictionaries) =>
      _dictionaries.replaceAll(dictionaries, skip: (d) => d.id == '');
  void replaceFolders(List<DictionaryFolder> folders) =>
      _folders.replaceAll(folders);

  @override
  Future<List<Dictionary>> getDictionaries({int keyLength = 0}) async =>
      getDictionariesSync(keyLength: keyLength);

  @override
  Future<Dictionary?> getDictionary(String id) async => _dictionaries.find(id);

  @override
  Future<Dictionary> saveDictionary(Dictionary dictionary) async {
    if (dictionary.id == '') return dictionary;
    return _dictionaries.save(dictionary);
  }

  @override
  Future<void> deleteDictionary(String id) async {
    _dictionaries.delete(id);
  }

  @override
  Future<List<DictionaryFolder>> getFolders() async => _folders.list();

  @override
  Future<DictionaryFolder> saveFolder(DictionaryFolder folder) async =>
      _folders.save(folder);

  @override
  Future<void> deleteFolder(String id, {bool deleteContents = true}) async {
    final folders = _folders.list();
    final folder = folders.where((f) => f.id == id).firstOrNull;
    if (folder == null) return;

    if (deleteContents) {
      final doomed = <String>{id};
      var grew = true;
      while (grew) {
        grew = false;
        for (final f in folders) {
          if (f.parentId != null &&
              doomed.contains(f.parentId) &&
              doomed.add(f.id)) {
            grew = true;
          }
        }
      }
      for (final d in _dictionaries.list()) {
        if (d.folderId != null && doomed.contains(d.folderId)) {
          _dictionaries.delete(d.id);
        }
      }
      for (final fid in doomed) {
        _folders.delete(fid);
      }
    } else {
      for (final f in folders) {
        if (f.parentId == id) {
          f.parentId = folder.parentId;
          _folders.save(f);
        }
      }
      for (final d in _dictionaries.list()) {
        if (d.folderId == id) {
          d.folderId = folder.parentId;
          _dictionaries.save(d);
        }
      }
      _folders.delete(id);
    }
  }

  @override
  Future<List<SyncTombstone>> getTombstones() async => _tombstones.all();

  @override
  Future<void> pruneTombstones(int olderThanMs) async =>
      _tombstones.prune(olderThanMs);

  @override
  Future<void> putDictionaryFromSync(Dictionary dictionary) async =>
      _dictionaries.putFromSync(dictionary);

  @override
  Future<void> putFolderFromSync(DictionaryFolder folder) async =>
      _folders.putFromSync(folder);

  @override
  Future<void> deleteFromSync(SyncTombstone tombstone) async {
    switch (tombstone.kind) {
      case SyncEntityKind.dictionary:
        _dictionaries.deleteFromSync(tombstone);
      case SyncEntityKind.dictionaryFolder:
        _folders.deleteFromSync(tombstone);
      case SyncEntityKind.card:
      case SyncEntityKind.cardFolder:
        throw ArgumentError('Not a dictionary tombstone: $tombstone');
    }
  }

  @override
  Stream<StoreChange> get changes => _bus.stream;
}
