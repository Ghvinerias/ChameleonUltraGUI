// SharedPreferences-backed [CardStore] (Track T7).
//
// Storage keys: `cards`, `card_folders` (unchanged, legacy compatible) and
// `card_tombstones` (new). Tombstones older than [retention] are pruned by
// [pruneExpired], which `SharedPreferencesProvider.load()` calls.
import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/prefs_collection.dart';
import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsCardStore implements CardStore {
  final Duration retention;
  final int Function() _clock;
  final StoreChangeBus _bus = StoreChangeBus();
  late final TombstoneLog _tombstones;
  late final PrefsCollection<CardSave> _cards;
  late final PrefsCollection<CardFolder> _folders;

  PrefsCardStore(
    SharedPreferences prefs, {
    int Function()? clock,
    this.retention = kDefaultTombstoneRetention,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _tombstones = TombstoneLog(prefs, 'card_tombstones');
    _cards = PrefsCollection<CardSave>(
      prefs: prefs,
      key: 'cards',
      kind: SyncEntityKind.card,
      tombstones: _tombstones,
      idOf: (c) => c.id,
      updatedAtOf: (c) => c.updatedAt,
      setUpdatedAt: (c, v) => c.updatedAt = v,
      toJson: (c) => c.toJson(),
      fromJson: CardSave.fromJson,
      clock: _clock,
      emit: _bus.add,
    );
    _folders = PrefsCollection<CardFolder>(
      prefs: prefs,
      key: 'card_folders',
      kind: SyncEntityKind.cardFolder,
      tombstones: _tombstones,
      idOf: (f) => f.id,
      updatedAtOf: (f) => f.updatedAt,
      setUpdatedAt: (f, v) => f.updatedAt = v,
      toJson: (f) => f.toJson(),
      fromJson: CardFolder.fromJson,
      clock: _clock,
      emit: _bus.add,
    );
  }

  /// Drops tombstones older than [retention].
  void pruneExpired() => _tombstones
      .prune(_clock() - retention.inMilliseconds);

  // Synchronous API used by the legacy SharedPreferencesProvider setters.
  List<CardSave> getCardsSync() => _cards.list();
  List<CardFolder> getFoldersSync() => _folders.list();
  void replaceCards(List<CardSave> cards) => _cards.replaceAll(cards);
  void replaceFolders(List<CardFolder> folders) =>
      _folders.replaceAll(folders);

  @override
  Future<List<CardSave>> getCards() async => _cards.list();

  @override
  Future<CardSave?> getCard(String id) async => _cards.find(id);

  @override
  Future<CardSave> saveCard(CardSave card) async => _cards.save(card);

  @override
  Future<void> deleteCard(String id) async {
    _cards.delete(id);
  }

  @override
  Future<List<CardFolder>> getFolders() async => _folders.list();

  @override
  Future<CardFolder> saveFolder(CardFolder folder) async =>
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
      for (final card in _cards.list()) {
        if (card.folderId != null && doomed.contains(card.folderId)) {
          _cards.delete(card.id);
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
      for (final card in _cards.list()) {
        if (card.folderId == id) {
          card.folderId = folder.parentId;
          _cards.save(card);
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
  Future<void> putCardFromSync(CardSave card) async =>
      _cards.putFromSync(card);

  @override
  Future<void> putFolderFromSync(CardFolder folder) async =>
      _folders.putFromSync(folder);

  @override
  Future<void> deleteFromSync(SyncTombstone tombstone) async {
    switch (tombstone.kind) {
      case SyncEntityKind.card:
        _cards.deleteFromSync(tombstone);
      case SyncEntityKind.cardFolder:
        _folders.deleteFromSync(tombstone);
      case SyncEntityKind.dictionary:
      case SyncEntityKind.dictionaryFolder:
        throw ArgumentError('Not a card tombstone: $tombstone');
    }
  }

  @override
  Stream<StoreChange> get changes => _bus.stream;
}
