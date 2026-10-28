import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionaries_screen.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_detail_page.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_download_page.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_downloader.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_selection.dart';
import 'package:chameleonultragui/wear/features/dictionaries/key_check_estimate.dart';
import 'package:chameleonultragui/wear/features/dictionaries/strings.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/wear_test_services.dart';

Dictionary dict(String name, int n, {int keyLength = 12, int seed = 0}) =>
    Dictionary(
      name: name,
      keyLength: keyLength,
      keys: List.generate(
        n,
        (i) => Uint8List.fromList(
          List.generate(keyLength ~/ 2, (j) => (i + j + seed) & 0xff),
        ),
      ),
    );

const goodFile = 'A0A1A2A3A4A5\nFFFFFFFFFFFF # default\nnot a key\n';

MockClient okClient(String body) =>
    MockClient((_) async => http.Response(body, 200));

/// Scrolls [f] into view in the page list, then taps it.
Future<void> tapScrolled(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 60);
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(f);
  await tester.pump();
}

Future<void> openDownload(WidgetTester tester) async {
  await tapScrolled(tester, find.text(DictStrings.download));
  await tester.pumpAndSettle();
}

/// Taps the first download source and lets everything settle.
Future<void> downloadFirst(WidgetTester tester) async {
  await openDownload(tester);
  await tapScrolled(tester, find.text(kDictionarySources.first.name));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('estimate', () {
    test('formula', () {
      expect(estimateKeyCheck(0), Duration.zero);
      expect(estimateKeyCheck(1), const Duration(milliseconds: 70 * 16));
      expect(estimateKeyCheck(33), const Duration(milliseconds: 2 * 70 * 16));
      expect(formatEstimate(const Duration(seconds: 45)), '45 s');
      expect(formatEstimate(const Duration(seconds: 180)), '3 min');
    });
  });

  group('WearDictionarySelection', () {
    test('default is all; explicit subset; stale ids ignored', () async {
      final rig = await createWearRig();
      final store = rig.services.dictionaryStore;
      final a = await store.saveDictionary(dict('a', 3));
      final b = await store.saveDictionary(dict('b', 2, seed: 9));
      await store.saveDictionary(dict('ul', 2, keyLength: 8));

      var active = await WearDictionarySelection.active(rig.services);
      expect(active.map((d) => d.id).toSet(), {a.id, b.id});

      await WearDictionarySelection.setSelectedIds({a.id, 'gone'});
      active = await WearDictionarySelection.active(rig.services);
      expect(active.map((d) => d.id), [a.id]);

      await WearDictionarySelection.setSelectedIds({});
      expect(await WearDictionarySelection.active(rig.services), isEmpty);

      await WearDictionarySelection.setSelectedIds(null);
      expect(await WearDictionarySelection.selectedIds(), isNull);
      active = await WearDictionarySelection.active(rig.services);
      expect(active.length, 2);
    });
  });

  group('list', () {
    testWidgets('empty state and hint', (tester) async {
      final rig = await createWearRig();
      await rig.pump(tester, const DictionariesScreen());
      await tester.pumpAndSettle();
      expect(find.text(DictStrings.empty), findsOneWidget);
      await tester.scrollUntilVisible(find.text(DictStrings.syncHint), 60);
      expect(find.text(DictStrings.syncHint), findsOneWidget);
      expect(find.text(DictStrings.useAll), findsNothing);
    });

    testWidgets('lists dictionaries with folders and totals', (tester) async {
      final rig = await createWearRig();
      final store = rig.services.dictionaryStore;
      final folder = await store.saveFolder(DictionaryFolder(name: 'Hotel'));
      await store.saveDictionary(dict('Default', 3));
      await store.saveDictionary(
        dict('Rooms', 2, seed: 7)..folderId = folder.id,
      );
      await rig.pump(tester, const DictionariesScreen());
      await tester.pumpAndSettle();
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Hotel', skipOffstage: false), findsOneWidget);
      expect(find.text('3 keys · 6-byte'), findsOneWidget);
      expect(find.textContaining('5 keys to try'), findsOneWidget);
    });

    testWidgets('toggle materialises selection, persists, Use all resets', (
      tester,
    ) async {
      final rig = await createWearRig();
      final store = rig.services.dictionaryStore;
      final a = await store.saveDictionary(dict('A', 3));
      final b = await store.saveDictionary(dict('B', 2, seed: 9));
      await rig.pump(tester, const DictionariesScreen());
      await tester.pumpAndSettle();
      expect(await WearDictionarySelection.selectedIds(), isNull);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      final ids = await WearDictionarySelection.selectedIds();
      expect(ids, isNotNull);
      expect(ids!.length, 1);
      expect(ids.contains(a.id) != ids.contains(b.id), isTrue);

      await tapScrolled(tester, find.text(DictStrings.useAll));
      await tester.pumpAndSettle();
      expect(await WearDictionarySelection.selectedIds(), isNull);
    });

    testWidgets('warns when many keys', (tester) async {
      final rig = await createWearRig();
      await rig.services.dictionaryStore.saveDictionary(dict('Big', 3000));
      await rig.pump(tester, const DictionariesScreen());
      await tester.pumpAndSettle();
      expect(find.text(DictStrings.largeWarning), findsOneWidget);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow at text scale $scale', (tester) async {
        final rig = await createWearRig();
        final store = rig.services.dictionaryStore;
        final f = await store.saveFolder(
          DictionaryFolder(name: 'A very long folder name for hotels'),
        );
        await store.saveDictionary(
          dict('Proxmark3 (Mifare Classic) long name', 40)..folderId = f.id,
        );
        await store.saveDictionary(dict('Short', 2, keyLength: 8));
        await rig.pump(tester, const DictionariesScreen(), textScale: scale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tapScrolled(tester, find.textContaining('Proxmark3'));
        await tester.pumpAndSettle();
        expect(find.byType(DictionaryDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(DictionaryDetailPage))).pop();
        await tester.pumpAndSettle();
        await openDownload(tester);
        expect(find.byType(DictionaryDownloadPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('detail', () {
    testWidgets('shows first keys and delete records a tombstone', (
      tester,
    ) async {
      final rig = await createWearRig();
      final store = rig.services.dictionaryStore;
      final d = await store.saveDictionary(dict('Del', 8));
      await WearDictionarySelection.setSelectedIds({d.id});
      await rig.pump(tester, const DictionariesScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Del'));
      await tester.pumpAndSettle();
      expect(find.text('000102030405'), findsOneWidget);
      expect(find.text('040506070809', skipOffstage: false), findsOneWidget);
      expect(
        find.text('050607080900', skipOffstage: false),
        findsNothing,
      ); // only 5 keys

      await tester.scrollUntilVisible(find.text(DictStrings.delete), 60);
      await tapScrolled(
        tester,
        find.widgetWithText(WearButton, DictStrings.delete),
      );
      await tester.pumpAndSettle();
      expect(find.text(DictStrings.deleteTitle), findsOneWidget);
      await tapScrolled(
        tester,
        find.widgetWithText(WearButton, DictStrings.delete),
      );
      await tester.pumpAndSettle();

      expect(await store.getDictionary(d.id), isNull);
      final tombs = await store.getTombstones();
      expect(tombs.map((t) => t.id), contains(d.id));
      expect(await WearDictionarySelection.selectedIds(), isEmpty);
      expect(find.byType(DictionaryDetailPage), findsNothing);
    });

    testWidgets('cancel keeps the dictionary', (tester) async {
      final rig = await createWearRig();
      final store = rig.services.dictionaryStore;
      final d = await store.saveDictionary(dict('Keep', 2));
      await rig.pump(tester, DictionaryDetailPage(dictionaryId: d.id));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(DictStrings.delete), 60);
      await tapScrolled(
        tester,
        find.widgetWithText(WearButton, DictStrings.delete),
      );
      await tester.pumpAndSettle();
      await tapScrolled(
        tester,
        find.widgetWithText(WearButton, DictStrings.cancel),
      );
      await tester.pumpAndSettle();
      expect(await store.getDictionary(d.id), isNotNull);
      expect(await store.getTombstones(), isEmpty);
    });
  });

  group('download', () {
    testWidgets('success saves via store', (tester) async {
      final rig = await createWearRig();
      await rig.pump(
        tester,
        DictionariesScreen(httpClient: okClient(goodFile)),
      );
      await tester.pumpAndSettle();
      await downloadFirst(tester);
      expect(
        find.text(DictStrings.saved(kDictionarySources.first.name, 2)),
        findsOneWidget,
      );
      final all = await rig.services.dictionaryStore.getDictionaries();
      expect(all.single.name, kDictionarySources.first.name);
      expect(all.single.keys.length, 2);
      expect(all.single.updatedAt, isNotNull);
    });

    testWidgets('same file twice is a duplicate', (tester) async {
      final rig = await createWearRig();
      await rig.pump(
        tester,
        DictionariesScreen(httpClient: okClient(goodFile)),
      );
      await tester.pumpAndSettle();
      await downloadFirst(tester);
      await tapScrolled(tester, find.text(kDictionarySources.last.name));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(DictStrings.duplicate), -60);
      expect(find.text(DictStrings.duplicate), findsOneWidget);
      expect((await rig.services.dictionaryStore.getDictionaries()).length, 1);
    });

    testWidgets('HTTP error', (tester) async {
      final rig = await createWearRig();
      final c = MockClient((_) async => http.Response('nope', 404));
      await rig.pump(tester, DictionariesScreen(httpClient: c));
      await tester.pumpAndSettle();
      await downloadFirst(tester);
      expect(find.text(DictStrings.httpError(404)), findsOneWidget);
      expect(await rig.services.dictionaryStore.getDictionaries(), isEmpty);
    });

    testWidgets('no network', (tester) async {
      final rig = await createWearRig();
      final c = MockClient((_) async => throw http.ClientException('offline'));
      await rig.pump(tester, DictionariesScreen(httpClient: c));
      await tester.pumpAndSettle();
      await downloadFirst(tester);
      expect(find.text(DictStrings.noNetwork), findsOneWidget);
    });

    testWidgets('malformed file', (tester) async {
      final rig = await createWearRig();
      await rig.pump(
        tester,
        DictionariesScreen(httpClient: okClient('<html>hello</html>')),
      );
      await tester.pumpAndSettle();
      await downloadFirst(tester);
      expect(find.text(DictStrings.malformed), findsOneWidget);
      expect(await rig.services.dictionaryStore.getDictionaries(), isEmpty);
    });

    testWidgets('oversize body', (tester) async {
      final rig = await createWearRig();
      final big = 'A0A1A2A3A4A5\n' * 200000; // > 2 MB
      await rig.pump(tester, DictionariesScreen(httpClient: okClient(big)));
      await tester.pumpAndSettle();
      await downloadFirst(tester);
      expect(
        find.text(DictStrings.tooLarge(kMaxDownloadBytes)),
        findsOneWidget,
      );
      expect(await rig.services.dictionaryStore.getDictionaries(), isEmpty);
    });

    testWidgets('timeout', (tester) async {
      final rig = await createWearRig();
      final never = Completer<http.Response>();
      final c = MockClient((_) => never.future);
      await rig.pump(
        tester,
        DictionaryDownloadPage(
          client: c,
          timeout: const Duration(milliseconds: 300),
        ),
      );
      await tester.pumpAndSettle();
      await tapScrolled(tester, find.text(kDictionarySources.first.name));
      await tester.pump();
      expect(find.text(DictStrings.downloading), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text(DictStrings.timeout), findsOneWidget);
    });

    testWidgets('cancel ignores a late result', (tester) async {
      final rig = await createWearRig();
      final gate = Completer<http.Response>();
      final c = MockClient((_) => gate.future);
      await rig.pump(tester, DictionaryDownloadPage(client: c));
      await tester.pumpAndSettle();
      await tapScrolled(tester, find.text(kDictionarySources.first.name));
      await tester.pump();
      await tapScrolled(tester, find.text(DictStrings.cancel));
      await tester.pump();
      gate.complete(http.Response(goodFile, 200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(DictStrings.cancelled, skipOffstage: false),
        findsOneWidget,
      );
      expect(await rig.services.dictionaryStore.getDictionaries(), isEmpty);
    });

    testWidgets('download into explicit selection auto-enables it', (
      tester,
    ) async {
      final rig = await createWearRig();
      await WearDictionarySelection.setSelectedIds({});
      await rig.pump(
        tester,
        DictionariesScreen(httpClient: okClient(goodFile)),
      );
      await tester.pumpAndSettle();
      await downloadFirst(tester);
      final all = await rig.services.dictionaryStore.getDictionaries();
      expect(await WearDictionarySelection.selectedIds(), {all.single.id});
    });
  });
}
