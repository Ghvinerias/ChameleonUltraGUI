import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which key dictionaries the watch uses when it checks Mifare Classic keys.
///
/// Stored watch-locally (SharedPreferences key [prefsKey]) as a list of
/// dictionary ids. `null` / unset means "use all dictionaries", which is the
/// default so a fresh install works without configuration.
///
/// Owned by the Dictionaries feature (F5); the Read feature (F1) calls
/// [active] to build its `HfReadOptions`.
class WearDictionarySelection {
  WearDictionarySelection._();

  static const prefsKey = 'wear.activeDictionaryIds';

  /// The selected dictionary ids, or null when the user never chose.
  static Future<Set<String>?> selectedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefsKey)?.toSet();
  }

  /// Persists the selection; pass null to go back to "all dictionaries".
  static Future<void> setSelectedIds(Set<String>? ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids == null) {
      await prefs.remove(prefsKey);
    } else {
      await prefs.setStringList(prefsKey, ids.toList()..sort());
    }
  }

  /// Dictionaries to use for key checks (6-byte keys: [keyLength] 12 hex
  /// digits), honouring the selection. Ids that no longer exist are ignored.
  static Future<List<Dictionary>> active(
    WearServices services, {
    int keyLength = 12,
  }) async {
    final all = await services.dictionaryStore.getDictionaries(
      keyLength: keyLength,
    );
    return dedupeKeys(resolve(all, await selectedIds()));
  }

  /// The same key often sits in several dictionaries (a downloaded list and
  /// an imported copy of it). Keeps each key once, in the order of the first
  /// dictionary that has it, so a key check never tries a key twice. Returns
  /// copies; dictionaries left without keys are dropped.
  static List<Dictionary> dedupeKeys(List<Dictionary> dictionaries) {
    final seen = <String>{};
    final result = <Dictionary>[];
    for (final d in dictionaries) {
      final unique = [
        for (final key in d.keys)
          if (seen.add(key.join(','))) key,
      ];
      if (unique.isEmpty) continue;
      result.add(
        Dictionary(
          id: d.id,
          name: d.name,
          keys: unique,
          color: d.color,
          keyLength: d.keyLength,
          folderId: d.folderId,
          updatedAt: d.updatedAt,
        ),
      );
    }
    return result;
  }

  /// Number of distinct keys across [dictionaries].
  static int uniqueKeyCount(Iterable<Dictionary> dictionaries) {
    final seen = <String>{};
    for (final d in dictionaries) {
      for (final key in d.keys) {
        seen.add(key.join(','));
      }
    }
    return seen.length;
  }

  /// Pure selection rule: null [ids] = all, otherwise the existing
  /// dictionaries whose id is in [ids] (stale ids are ignored).
  static List<Dictionary> resolve(List<Dictionary> all, Set<String>? ids) {
    if (ids == null) return all;
    return all.where((d) => ids.contains(d.id)).toList();
  }

  /// Switches one dictionary on or off. The first call with a null selection
  /// materialises the explicit set from [all] (every current dictionary).
  /// Returns the new selection.
  static Future<Set<String>> setUsed(
    String id,
    bool used, {
    required Iterable<Dictionary> all,
  }) async {
    final ids = {...(await selectedIds() ?? all.map((d) => d.id))};
    used ? ids.add(id) : ids.remove(id);
    await setSelectedIds(ids);
    return ids;
  }
}
