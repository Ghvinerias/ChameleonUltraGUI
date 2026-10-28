import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/wear/features/saved_cards/strings.dart';

/// One line of the flattened card list.
sealed class SavedRow {
  const SavedRow();
}

/// Section header: the folder path ("Work / Doors"), or null for cards that
/// are not in any folder.
class FolderHeaderRow extends SavedRow {
  const FolderHeaderRow(this.path);
  final String? path;
}

class CardRow extends SavedRow {
  const CardRow(this.card);
  final CardSave card;
}

/// Flattens the folder tree into section headers followed by their cards.
///
/// Unfiled cards come first (with a header only when folders are also shown),
/// then one section per non-empty folder ordered by path. Inside a section
/// the most recently updated card is first. A folder whose parent no longer
/// exists is shown by its own name (the phone moves it to the root on sync).
List<SavedRow> buildSavedRows(List<CardSave> cards, List<CardFolder> folders) {
  final byId = {for (final f in folders) f.id: f};
  final pathCache = <String, String>{};

  String pathOf(String id) => pathCache.putIfAbsent(id, () {
    final names = <String>[];
    final seen = <String>{};
    String? cursor = id;
    while (cursor != null && seen.add(cursor)) {
      final f = byId[cursor];
      if (f == null) break;
      names.add(f.name);
      cursor = f.parentId;
    }
    return names.reversed.join(' / ');
  });

  final unfiled = <CardSave>[];
  final groups = <String, List<CardSave>>{};
  for (final c in cards) {
    final fid = c.folderId;
    if (fid == null || !byId.containsKey(fid)) {
      unfiled.add(c);
    } else {
      (groups[fid] ??= []).add(c);
    }
  }

  int newestFirst(CardSave a, CardSave b) {
    final d = (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
    return d != 0 ? d : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  final rows = <SavedRow>[];
  final showFolders = groups.isNotEmpty;
  if (unfiled.isNotEmpty) {
    if (showFolders) rows.add(const FolderHeaderRow(null));
    rows.addAll((unfiled..sort(newestFirst)).map(CardRow.new));
  }
  final ids = groups.keys.toList()
    ..sort(
      (a, b) => pathOf(a).toLowerCase().compareTo(pathOf(b).toLowerCase()),
    );
  for (final id in ids) {
    rows.add(FolderHeaderRow(pathOf(id)));
    rows.addAll((groups[id]!..sort(newestFirst)).map(CardRow.new));
  }
  return rows;
}

/// Same rule as `SlotServiceImpl.canUpload`, for when no device is connected
/// (the service only exists while connected). A test keeps the two in sync.
bool cardTypeLoadable(TagType tag) =>
    isMifareClassic(tag) ||
    isMifareUltralight(tag) ||
    tag == TagType.hf14a4 ||
    isEM410X(tag) ||
    const {
      TagType.hidProx,
      TagType.viking,
      TagType.pac,
      TagType.ioProx,
      TagType.idteck,
    }.contains(tag);

bool isHighFrequency(CardSave card) =>
    chameleonTagToFrequency(card.tag) == TagFrequency.hf;

String cardTypeLabel(CardSave card, AppLocalizations l) =>
    chameleonCardToString(card, l);

String cardDisplayName(CardSave card) =>
    card.name.trim().isEmpty ? SavedCardsStrings.unnamed : card.name;

String hexBytes(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// "64/64 blocks, 12/16 sectors keys known", "135 pages", "ID only"... or
/// null when there is nothing to say.
String? dumpSummary(CardSave card) {
  final filled = card.data.where((b) => b.isNotEmpty).length;
  if (isMifareClassic(card.tag)) {
    final isEv1 = chameleonTagSaveCheckForMifareClassicEV1(card);
    final type = chameleonTagTypeGetMfClassicType(card.tag);
    final blocks = mfClassicGetBlockCount(type, isEV1: isEv1);
    final sectors = mfClassicGetSectorCount(type, isEV1: isEv1);
    var known = 0;
    for (var s = 0; s < sectors; s++) {
      final t = mfClassicGetSectorTrailerBlockBySector(s);
      if (t < card.data.length && card.data[t].isNotEmpty) known++;
    }
    return '${SavedCardsStrings.dumpBlocks(filled, blocks)}, '
        '${SavedCardsStrings.dumpSectors(known, sectors)}';
  }
  if (isMifareUltralight(card.tag)) {
    return SavedCardsStrings.dumpPages(filled);
  }
  return SavedCardsStrings.noDump;
}
