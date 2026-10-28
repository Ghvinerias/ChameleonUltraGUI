import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/ui/strings.dart';
import 'package:chameleonultragui/sync/ui/sync_check.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:chameleonultragui/sync/ui/watch_sync_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/in_memory_card_store.dart';
import '../../fakes/in_memory_dictionary_store.dart';
import '../../fakes/in_memory_sync_transport.dart';
import 'sync_ui_harness.dart';

Widget page(
  InMemorySyncTransport? t,
  InMemoryCardStore c,
  InMemoryDictionaryStore d, {
  SyncLinkFactory? link,
}) => MaterialApp(
  home: WatchSyncPage(
    cards: c,
    dictionaries: d,
    linkFactory: link ?? readyLink(t!),
    options: fastOptions,
    initialMirror: false,
  ),
);

void main() {
  late InMemorySyncTransport phoneT;
  late InMemorySyncTransport watchT;
  late InMemoryCardStore pc, wc;
  late InMemoryDictionaryStore pd, wd;

  setUp(() {
    final (p, w) = InMemorySyncTransport.pair();
    phoneT = p;
    watchT = w;
    pc = InMemoryCardStore();
    pd = InMemoryDictionaryStore();
    wc = InMemoryCardStore();
    wd = InMemoryDictionaryStore();
  });

  testWidgets('unsupported platform shows a clear message and no actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        null,
        pc,
        pd,
        link: unsupportedLink(SyncUnsupportedReason.notAndroid),
      ),
    );
    await tester.pump();
    expect(
      find.text(SyncStrings.unsupportedBody(SyncUnsupportedReason.notAndroid)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sync-now')), findsNothing);
    expect(find.byKey(const Key('check-run')), findsNothing);
  });

  testWidgets('no Play Services message', (tester) async {
    await tester.pumpWidget(
      page(
        null,
        pc,
        pd,
        link: unsupportedLink(SyncUnsupportedReason.noPlayServices),
      ),
    );
    await tester.pump();
    expect(
      find.text(
        SyncStrings.unsupportedTitle(SyncUnsupportedReason.noPlayServices),
      ),
      findsOneWidget,
    );
  });

  testWidgets('peer unavailable disables Sync now', (tester) async {
    phoneT.setPeerAvailable(false);
    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    expect(find.text(SyncStrings.peerUnavailable), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const Key('sync-now')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('full sync renders the report and converges', (tester) async {
    await seedCard(pc, 'c1', 1000);
    await seedDict(pd, 'd1', 1000);
    await seedCard(wc, 'c2', 2000);
    final watch = rawEngine(SyncRole.watch, watchT, wc, wd)..start();
    addTearDown(watch.dispose);
    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    expect(find.text(SyncStrings.peerAvailablePhone), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pump();
    await settle(
      tester,
      () => find.byKey(const Key('sync-report')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('sync-report')), findsOneWidget);
    expect((await pc.getCards()).length, 2);
    expect((await wc.getCards()).length, 2);
    expect((await wd.getDictionaries()).length, 1);
    expect(find.textContaining('Cards: +1'), findsWidgets);
    expect(find.textContaining('Cards: 2'), findsOneWidget); // library
  });

  testWidgets('shows progress and cancel stops the sync', (tester) async {
    await seedCard(pc, 'c1', 1000, dataBytes: 200000);
    final watch = rawEngine(SyncRole.watch, watchT, wc, wd)..start();
    addTearDown(watch.dispose);
    // Stalling the link spins the engine's resend loop under fake time, so
    // press the page's own Cancel button from inside the transfer instead.
    var sent = 0;
    phoneT.chunkHook = (c) {
      if (++sent == 3) {
        tester
            .widget<OutlinedButton>(find.byKey(const Key('sync-cancel')))
            .onPressed!();
      }
      return ChunkFate.deliver;
    };
    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pump();
    expect(find.byKey(const Key('sync-progress')), findsOneWidget);
    expect(find.byKey(const Key('sync-phase')), findsOneWidget);
    await settle(
      tester,
      () => find.byKey(const Key('sync-error')).evaluate().isNotEmpty,
    );
    expect(find.text('Sync cancelled. Nothing was changed.'), findsOneWidget);
    expect(find.byKey(const Key('sync-progress')), findsNothing);
    expect(await wc.getCards(), isEmpty);
    expect(await pc.getCards(), hasLength(1));
  });

  testWidgets('version mismatch is explained', (tester) async {
    final watch = rawEngine(
      SyncRole.watch,
      watchT,
      wc,
      wd,
      protocolVersion: 99,
      minProtocolVersion: 99,
    )..start();
    addTearDown(watch.dispose);
    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sync-now')));
    await settle(
      tester,
      () => find.byKey(const Key('sync-error')).evaluate().isNotEmpty,
    );
    expect(find.textContaining('different sync versions'), findsOneWidget);
  });

  testWidgets('silent peer app ends in "not reachable"', (tester) async {
    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sync-now')));
    await settle(
      tester,
      () => find.byKey(const Key('sync-error')).evaluate().isNotEmpty,
    );
    expect(find.textContaining('not reachable'), findsOneWidget);
  });

  testWidgets('sync check passes and fails with numbers', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A responder on the watch end (no engine: it would drain check bulks).
    final responder = SyncCheck(transport: SyncTransportSplit(watchT).checkView)
      ..startResponder();
    addTearDown(responder.dispose);

    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    await tester.tap(find.byKey(const Key('check-run')));
    await settle(
      tester,
      () => find.byKey(const Key('check-verdict')).evaluate().isNotEmpty,
      maxMs: 30000,
    );
    expect(find.text(SyncStrings.checkPass), findsOneWidget);
    expect(find.textContaining('KB/s'), findsNWidgets(2));
    expect(find.textContaining('ms ('), findsOneWidget);

    phoneT.chunkHook = (c) {
      c.bytes[0] ^= 1;
      return ChunkFate.deliver;
    };
    await tester.tap(find.byKey(const Key('check-run')));
    await settle(
      tester,
      () => find.text(SyncStrings.checkFail).evaluate().isNotEmpty,
      maxMs: 30000,
    );
    expect(find.text(SyncStrings.checkFail), findsOneWidget);
    expect(
      find.text('peer rejected it: integrity check failed'),
      findsOneWidget,
    );
  });

  testWidgets('disposing the page releases the transport', (tester) async {
    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    for (var i = 0; i < 100 && !closed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      try {
        await phoneT.sendMessage(const SyncMessage(type: 'x'));
      } on StateError {
        closed = true;
      }
    }
    expect(closed, isTrue);
  });

  testWidgets('no overflow on a narrow phone at text scale 1.3', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    await seedCard(pc, 'c1', 1);
    final watch = rawEngine(SyncRole.watch, watchT, wc, wd)..start();
    addTearDown(watch.dispose);
    await tester.pumpWidget(page(phoneT, pc, pd));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sync-now')));
    await settle(
      tester,
      () => find.byKey(const Key('sync-report')).evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
