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
    return resolve(all, await selectedIds());
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
