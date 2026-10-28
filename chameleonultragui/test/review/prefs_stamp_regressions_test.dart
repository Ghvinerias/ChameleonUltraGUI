// Review findings for T7 (prefs-backed stores). Each test FAILS on the current
// code on purpose; see docs/review-phone-regressions.md (findings P1, P2, P3).
import 'package:chameleonultragui/core/stores/prefs_card_store.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CardSave card(String id, String name) =>
    CardSave(id: id, uid: '01020304', name: name, tag: TagType.mifare1K);

void main() {
  test('P1: edit within the same millisecond must still advance updatedAt',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = PrefsCardStore(prefs, clock: () => 1000);

    store.replaceCards([card('a', 'one')]);
    final first = store.getCardsSync().single.updatedAt!;
    store.replaceCards([card('a', 'two')]);
    final second = store.getCardsSync().single.updatedAt!;

    // Last-writer-wins sync cannot order two edits with an identical stamp.
    expect(second, greaterThan(first));
  });

  test('P1: edit after the device clock moved backwards must not lower updatedAt',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = 5000;
    final store = PrefsCardStore(prefs, clock: () => now);

    store.replaceCards([card('a', 'one')]);
    final first = store.getCardsSync().single.updatedAt!;
    now = 1000; // clock skew / manual time change
    store.replaceCards([card('a', 'two')]);
    final second = store.getCardsSync().single.updatedAt!;

    // A newer local edit now looks older than the edit it replaced.
    expect(second, greaterThanOrEqualTo(first));
  });

  test('P2: tombstone must not be older than the entity it deletes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = 5000;
    final store = PrefsCardStore(prefs, clock: () => now);

    store.replaceCards([card('a', 'one')]);
    final stamp = store.getCardsSync().single.updatedAt!;
    now = 1000;
    store.replaceCards([]);

    final tombstone = (await store.getTombstones())
        .singleWhere((t) => t.kind == SyncEntityKind.card && t.id == 'a');
    // Otherwise a peer holding the card (updatedAt 5000) resurrects it.
    expect(tombstone.deletedAt, greaterThanOrEqualTo(stamp));
  });

  test('P3: setCards must still work when a stored entry is unreadable',
      () async {
    // Old setCards() never read storage, so it could overwrite a corrupt list.
    SharedPreferences.setMockInitialValues({
      'cards': <String>['{not json'],
    });
    final provider = SharedPreferencesProvider();
    await provider.load();

    expect(() => provider.setCards([card('a', 'fresh')]), returnsNormally);
  });

  test('P3: setDictionaries must still work when a stored entry is unreadable',
      () async {
    SharedPreferences.setMockInitialValues({
      'dictionaries': <String>['{not json'],
    });
    final provider = SharedPreferencesProvider();
    await provider.load();

    expect(() => provider.setDictionaries([Dictionary(id: 'd', name: 'n')]),
        returnsNormally);
  });
}
