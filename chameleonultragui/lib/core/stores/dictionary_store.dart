// FROZEN CONTRACT (Track 0B). Changes require a PR labelled `contract-change`.
//
// Persistence of key dictionaries and dictionary folders.
//
// Implemented by Track T7 over SharedPreferences, replacing direct
// `SharedPreferencesProvider.getDictionaries/setDictionaries/
// getDictionaryFolders/setDictionaryFolders` calls in
// lib/gui/menu/dialogs/dictionary/** and lib/gui/page/saved_cards.dart.
//
// SYNC RULES: identical to `CardStore` (stamp `updatedAt` on every
// create/update, record a `SyncTombstone` on every delete, `*FromSync` applies
// verbatim, `changes` fires after persistence).
//
// The "system empty dictionary" (id == "") is never persisted nor
// synchronised; `saveDictionary` ignores it (matches `setDictionaries`).
import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';

abstract class DictionaryStore {
  /// All dictionaries; [keyLength] 0 means any, else only matching
  /// `Dictionary.keyLength` (same filter as `getDictionaries`).
  Future<List<Dictionary>> getDictionaries({int keyLength = 0});

  Future<Dictionary?> getDictionary(String id);

  /// Creates or updates; stamps `updatedAt`; returns the stored copy.
  Future<Dictionary> saveDictionary(Dictionary dictionary);

  Future<void> deleteDictionary(String id);

  Future<List<DictionaryFolder>> getFolders();

  Future<DictionaryFolder> saveFolder(DictionaryFolder folder);

  /// See `CardStore.deleteFolder`.
  Future<void> deleteFolder(String id, {bool deleteContents = true});

  Future<List<SyncTombstone>> getTombstones();

  Future<void> pruneTombstones(int olderThanMs);

  Future<void> putDictionaryFromSync(Dictionary dictionary);
  Future<void> putFolderFromSync(DictionaryFolder folder);
  Future<void> deleteFromSync(SyncTombstone tombstone);

  Stream<StoreChange> get changes;
}
