import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/ui/strings.dart';
import 'package:chameleonultragui/sync/ui/sync_check.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:chameleonultragui/sync/ui/watch_sync_page.dart';
import 'package:chameleonultragui/wear/features/sync/strings.dart';
import 'package:chameleonultragui/wear/features/sync/sync_screen.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/in_memory_card_store.dart';
import '../../../fakes/in_memory_dictionary_store.dart';
import '../../../fakes/in_memory_sync_transport.dart';
import '../../../sync/ui/sync_ui_harness.dart';
import '../../kit/wear_test_harness.dart';
import '../../support/wear_test_services.dart';

SyncScreen screen(SyncLinkFactory link) =>
    SyncScreen(key: UniqueKey(), linkFactory: link, options: fastOptions);

Future<void> reveal(WidgetTester tester, String key) async {
  // Back to the top first: the item may be above the current position.
  await tester.fling(find.byType(ListView), const Offset(0, 3000), 5000);
  await tester.pump(const Duration(seconds: 2));
  await tester.dragUntilVisible(
    find.byKey(Key(key)),
    find.byType(ListView),
    const Offset(0, -120),
  );
  // Centre it: the screen is round, so taps near the corners miss.
  await Scrollable.ensureVisible(
    tester.element(find.byKey(Key(key))),
    alignment: 0.5,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Drops the watch's handshake answers so a session shows as "running" on the
/// watch (hello seen, nothing else) until it is cancelled.
ChunkFate dropHelloAck(SyncMessage m) =>
    m.type == 'sync.hello-ack' ? ChunkFate.drop : ChunkFate.deliver;

Future<void> seedWatchCard(
  WearTestRig rig,
  String id,
  int stamp, {
  int dataBytes = 4,
}) async {
  final tmp = InMemoryCardStore();
  await seedCard(tmp, id, stamp, dataBytes: dataBytes);
  await rig.prefs.cardStore.putCardFromSync((await tmp.getCards()).single);
}

void main() {
  late InMemorySyncTransport phoneT;
  late InMemorySyncTransport watchT;
  late InMemoryCardStore pc;
  late InMemoryDictionaryStore pd;

  setUp(() {
    final (p, w) = InMemorySyncTransport.pair();
    phoneT = p;
    watchT = w;
    pc = InMemoryCardStore();
    pd = InMemoryDictionaryStore();
  });

  bool shown(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

  testWidgets('says it waits for the phone and cannot start a sync', (
    tester,
  ) async {
    final rig = await createWearRig();
    await rig.pump(tester, screen(readyLink(watchT)));
    await tester.pump();
    expect(find.text(WatchSyncStrings.phoneConnected), findsOneWidget);
    expect(find.text(WatchSyncStrings.waitingForPhone), findsOneWidget);
    await tester.dragUntilVisible(
      find.text(WatchSyncStrings.mirrorNote),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.text(WatchSyncStrings.mirrorNote), findsOneWidget);
    expect(find.text(SyncStrings.syncNow), findsNothing);
  });

  testWidgets('peer unavailable and unsupported states', (tester) async {
    final rig = await createWearRig();
    watchT.setPeerAvailable(false);
    await rig.pump(tester, screen(readyLink(watchT)));
    await tester.pump();
    expect(find.text(SyncStrings.peerUnavailable), findsOneWidget);
    expect(find.text(WatchSyncStrings.peerUnavailableHint), findsOneWidget);

    await rig.pump(
      tester,
      screen(unsupportedLink(SyncUnsupportedReason.noPlayServices)),
    );
    await tester.pump();
    expect(
      find.text(
        SyncStrings.unsupportedTitle(SyncUnsupportedReason.noPlayServices),
      ),
      findsOneWidget,
    );
    expect(find.text(SyncStrings.checkRun), findsNothing);
  });

  testWidgets('phone page and watch screen sync each other end to end', (
    tester,
  ) async {
    final rig = await createWearRig();
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockRotaryChannel();

    await seedCard(pc, 'p1', 1000);
    await seedDict(pd, 'pd1', 1000);
    await seedWatchCard(rig, 'w1', 2000);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            Expanded(
              child: MaterialApp(
                home: WatchSyncPage(
                  cards: pc,
                  dictionaries: pd,
                  linkFactory: readyLink(phoneT),
                  options: fastOptions,
                  initialMirror: false,
                ),
              ),
            ),
            Expanded(
              child: WearServicesScope(
                services: rig.services,
                child: wearMaterial(screen(readyLink(watchT))),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final onWatch = find.byType(SyncScreen);
    final onPhone = find.byType(WatchSyncPage);
    expect(
      find.descendant(of: onWatch, matching: find.text('Waiting for phone')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: onPhone, matching: find.byKey(const Key('sync-now'))),
    );
    await settle(
      tester,
      () =>
          find
              .descendant(
                of: onWatch,
                matching: find.byKey(const Key('sync-report')),
              )
              .evaluate()
              .isNotEmpty &&
          find
              .descendant(
                of: onPhone,
                matching: find.byKey(const Key('sync-report')),
              )
              .evaluate()
              .isNotEmpty,
    );
    expect(
      find.descendant(
        of: onWatch,
        matching: find.byKey(const Key('sync-report')),
      ),
      findsOneWidget,
    );
    // The watch received one card and one dictionary and sent nothing new.
    expect(
      find.descendant(of: onWatch, matching: find.text('Cards')),
      findsWidgets,
    );
    expect(
      find.descendant(of: onWatch, matching: find.text('+1  ~0  -0')),
      findsNWidgets(2),
    );
    expect(await rig.prefs.cardStore.getCards(), hasLength(2));
    expect(await pc.getCards(), hasLength(2));
    expect(await rig.prefs.dictionaryStore.getDictionaries(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows progress and Cancel on the watch stops the sync', (
    tester,
  ) async {
    final rig = await createWearRig();
    await seedWatchCard(rig, 'w1', 2000);
    final phone = rawEngine(
      SyncRole.phone,
      phoneT,
      pc,
      pd,
      options: patientOptions,
    )..start();
    addTearDown(phone.dispose);
    await rig.pump(tester, screen(readyLink(watchT)));
    await tester.pump();

    watchT.messageHook = dropHelloAck;
    Object? phoneError;
    phone.startSync().result.then<void>(
      (_) {},
      onError: (Object e) {
        phoneError = e;
      },
    );
    await settle(tester, () => shown('sync-progress'));
    expect(shown('sync-progress'), isTrue);
    expect(shown('sync-phase'), isTrue);
    expect(find.text('Waiting for phone'), findsNothing);

    await reveal(tester, 'sync-cancel');
    await tester.tap(find.byKey(const Key('sync-cancel')));
    await settle(tester, () => shown('sync-error'));
    await reveal(tester, 'sync-error');
    expect(find.text('Sync cancelled. Nothing was changed.'), findsOneWidget);
    expect(shown('sync-progress'), isFalse);
    await settle(tester, () => phoneError != null);
    expect(phoneError, isNotNull);
    expect(await pc.getCards(), isEmpty);
  });

  testWidgets('a phone with another protocol version is explained', (
    tester,
  ) async {
    final rig = await createWearRig();
    await rig.pump(tester, screen(readyLink(watchT)));
    await tester.pump();
    final phone = rawEngine(
      SyncRole.phone,
      phoneT,
      pc,
      pd,
      protocolVersion: 99,
      minProtocolVersion: 99,
    )..start();
    addTearDown(phone.dispose);
    phone.startSync().result.ignore();
    await settle(tester, () => shown('sync-error'));
    expect(find.textContaining('different sync versions'), findsOneWidget);
  });

  testWidgets('sync check from the watch passes, then fails on corruption', (
    tester,
  ) async {
    final rig = await createWearRig();
    final responder = SyncCheck(transport: SyncTransportSplit(phoneT).checkView)
      ..startResponder();
    addTearDown(responder.dispose);
    await rig.pump(tester, screen(readyLink(watchT)));
    await tester.pump();
    await tester.dragUntilVisible(
      find.byKey(const Key('check-run')),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.tap(find.byKey(const Key('check-run')));
    await settle(tester, () => shown('check-verdict'), maxMs: 30000);
    await reveal(tester, 'check-receive');
    expect(
      find.text(SyncStrings.checkPass, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('KB/s'), findsNWidgets(2));

    watchT.chunkHook = (c) {
      c.bytes[1] ^= 0x10;
      return ChunkFate.deliver;
    };
    await reveal(tester, 'check-run');
    await tester.tap(find.byKey(const Key('check-run')));
    await settle(
      tester,
      () => find
          .text(SyncStrings.checkFail, skipOffstage: false)
          .evaluate()
          .isNotEmpty,
      maxMs: 30000,
    );
    await reveal(tester, 'check-send');
    expect(
      find.text(SyncStrings.checkFail, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('peer rejected it: integrity check failed'),
      findsOneWidget,
    );
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('no overflow at 206 dp, text scale $scale', (tester) async {
      final rig = await createWearRig();
      await seedWatchCard(rig, 'w1', 2000, dataBytes: 200000);
      await seedCard(pc, 'p1', 1000);
      await seedDict(pd, 'pd1', 1000);
      final split = SyncTransportSplit(phoneT);
      final responder = SyncCheck(transport: split.checkView)..startResponder();
      addTearDown(responder.dispose);
      final phone = rawEngine(
        SyncRole.phone,
        split.engineView,
        pc,
        pd,
        options: patientOptions,
      )..start();
      addTearDown(phone.dispose);

      await rig.pump(tester, screen(readyLink(watchT)), textScale: scale);
      await tester.pump();
      expect(tester.takeException(), isNull); // waiting

      // A run in flight (progress ring), then cancelled on the watch.
      watchT.messageHook = dropHelloAck;
      phone.startSync().result.ignore();
      await settle(tester, () => shown('sync-progress'));
      expect(shown('sync-progress'), isTrue);
      expect(tester.takeException(), isNull); // running
      await reveal(tester, 'sync-cancel');
      await tester.tap(find.byKey(const Key('sync-cancel')));
      await settle(tester, () => shown('sync-error'));
      expect(tester.takeException(), isNull); // error

      await settle(tester, () => !phone.isSyncing);
      watchT.messageHook = null;
      phone.startSync().result.ignore();
      await settle(tester, () => shown('sync-report'));
      expect(shown('sync-report'), isTrue);
      expect(tester.takeException(), isNull); // report

      await reveal(tester, 'check-run');
      await tester.tap(find.byKey(const Key('check-run')));
      await settle(tester, () => shown('check-verdict'), maxMs: 30000);
      await reveal(tester, 'check-receive');
      expect(tester.takeException(), isNull); // check results
    });
  }
}
