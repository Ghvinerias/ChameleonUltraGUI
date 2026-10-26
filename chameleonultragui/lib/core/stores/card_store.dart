// FROZEN CONTRACT (Track 0B). Changes require a PR labelled `contract-change`.
//
// Persistence of saved cards and card folders.
//
// Implemented by Track T7 over SharedPreferences, replacing the direct
// `SharedPreferencesProvider.getCards/setCards/getCardFolders/setCardFolders`
// calls in lib/gui/page/saved_cards.dart and lib/gui/menu/dialogs/card/**.
//
// SYNC RULES (every implementation MUST honour these):
//  * Every create or update through [saveCard] / [saveFolder] stamps
//    `updatedAt` with the current epoch milliseconds (from an injectable
//    clock) on the stored entity, overwriting whatever the caller set.
//  * Every [deleteCard] / [deleteFolder] records a [SyncTombstone]
//    (`deletedAt` = now) for each removed entity (including cards removed
//    with a folder), and removes any older tombstone for the same id when an
//    entity with that id is created again.
//  * The `*FromSync` methods apply remote state VERBATIM: no restamping, no
//    new tombstone beyond the one supplied. Sync engine (T4) is their only
//    caller.
//  * [changes] fires after persistence, once per affected entity.
import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';

abstract class CardStore {
  /// All saved cards (any folder).
  Future<List<CardSave>> getCards();

  Future<CardSave?> getCard(String id);

  /// Creates or updates (matched by `card.id`). Stamps `updatedAt`. Returns
  /// the stored copy.
  Future<CardSave> saveCard(CardSave card);

  /// Deletes a card; no-op (and no tombstone) if it does not exist.
  Future<void> deleteCard(String id);

  Future<List<CardFolder>> getFolders();

  /// Creates or updates a folder. Stamps `updatedAt`.
  Future<CardFolder> saveFolder(CardFolder folder);

  /// Deletes a folder. With [deleteContents] true (current phone behaviour)
  /// the whole subtree of folders and cards is removed, each with a
  /// tombstone; false re-parents direct children to the folder's parent.
  Future<void> deleteFolder(String id, {bool deleteContents = true});

  /// All recorded deletions not yet pruned.
  Future<List<SyncTombstone>> getTombstones();

  /// Drops tombstones with `deletedAt` older than [olderThanMs] (epoch ms).
  /// The sync engine calls this after both peers acknowledged them.
  Future<void> pruneTombstones(int olderThanMs);

  /// Sync-apply entry points (no restamping), see class comment.
  Future<void> putCardFromSync(CardSave card);
  Future<void> putFolderFromSync(CardFolder folder);
  Future<void> deleteFromSync(SyncTombstone tombstone);

  /// Broadcast stream of persisted changes.
  Stream<StoreChange> get changes;
}
