// Merge helpers for the sync engine (Track T4). Additive extensions only; the
// model classes themselves are frozen.
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';

/// Stamp used by the merge rules: a missing `updatedAt` counts as 0.
int syncStampOf(int? updatedAt) => updatedAt ?? 0;

extension CardSaveSync on CardSave {
  SyncEntityKind get syncKind => SyncEntityKind.card;
  int get syncStamp => syncStampOf(updatedAt);
}

extension CardFolderSync on CardFolder {
  SyncEntityKind get syncKind => SyncEntityKind.cardFolder;
  int get syncStamp => syncStampOf(updatedAt);
}

extension DictionarySync on Dictionary {
  SyncEntityKind get syncKind => SyncEntityKind.dictionary;
  int get syncStamp => syncStampOf(updatedAt);

  /// The system "empty" dictionary (id "") is never persisted or synced.
  bool get isSyncable => id.isNotEmpty;
}

extension DictionaryFolderSync on DictionaryFolder {
  SyncEntityKind get syncKind => SyncEntityKind.dictionaryFolder;
  int get syncStamp => syncStampOf(updatedAt);
}

extension SyncEntityKindFamily on SyncEntityKind {
  bool get isFolder =>
      this == SyncEntityKind.cardFolder ||
      this == SyncEntityKind.dictionaryFolder;

  bool get isCardFamily =>
      this == SyncEntityKind.card || this == SyncEntityKind.cardFolder;

  bool get isDictionaryFamily => !isCardFamily;

  /// The folder kind items of this kind live in (folders: their own kind).
  SyncEntityKind get folderKind => isCardFamily
      ? SyncEntityKind.cardFolder
      : SyncEntityKind.dictionaryFolder;

  /// JSON field holding the containing folder id.
  String get parentField => isFolder ? 'parentId' : 'folderId';
}
