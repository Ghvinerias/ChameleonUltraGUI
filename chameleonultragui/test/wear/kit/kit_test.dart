import 'package:chameleonultragui/wear/app.dart';
import 'package:chameleonultragui/wear/gallery/widget_gallery.dart';
import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:chameleonultragui/wear/navigation/wear_destinations.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/round_list_view.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wear_test_harness.dart';

const homeTitles = [
  'Read',
  'Slots',
  'Saved cards',
  'Dictionaries',
  'Device',
  'Sync',
  'Diagnostics',
];

void main() {
  setUpAll(mockRotaryChannel);
  setUp(WearDestinations.clear);

  for (final scale in [1.0, 1.3]) {
    group('text scale $scale', () {
      testWidgets('home: every entry reachable, no overflow', (tester) async {
        await pumpWear(tester, const WearApp(), textScale: scale);
        for (final t in homeTitles) {
          await tester.scrollUntilVisible(
            find.text(t),
            60,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text(t), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('gallery renders without overflow', (tester) async {
        await pumpWear(
          tester,
          wearMaterial(const WidgetGallery(animate: false)),
          textScale: scale,
        );
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 30; i++) {
          await tester.drag(scrollable, const Offset(0, -150));
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('tiles are at least 48dp tall', (tester) async {
        await pumpWear(tester, const WearApp(), textScale: scale);
        for (final e in tester.widgetList<CompactListTile>(
          find.byType(CompactListTile),
        )) {
          final h = tester.getSize(find.byWidget(e)).height;
          expect(h, greaterThanOrEqualTo(48));
        }
      });
    });
  }

  testWidgets('placeholder opens for non-diagnostic entries', (tester) async {
    await pumpWear(tester, const WearApp());
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('placeholder fits at scale 1.3', (tester) async {
    await pumpWear(tester, const WearApp(), textScale: 1.3);
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registered destination replaces placeholder', (tester) async {
    await pumpWear(tester, const WearApp(registerDestinations: false));
    WearDestinations.register(
      WearDestinationId.slots,
      (_) => const Scaffold(body: Text('real slots')),
    );
    await tester.tap(find.text('Slots'));
    await tester.pumpAndSettle();
    expect(find.text('real slots'), findsOneWidget);
  });

  testWidgets('Diagnostics opens the spike launcher', (tester) async {
    await pumpWear(tester, const WearApp());
    await tester.scrollUntilVisible(
      find.text('Diagnostics'),
      60,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Spike G0'), findsOneWidget);
  });

  testWidgets('rotary deltas scroll the list; sign positive = down', (
    tester,
  ) async {
    final rotary = RotaryController.fake();
    final controller = ScrollController();
    await pumpWear(
      tester,
      wearMaterial(
        RotaryScope(
          controller: rotary,
          child: RoundListView(
            controller: controller,
            haptics: false,
            children: [
              for (var i = 0; i < 30; i++) CompactListTile(title: 'Row $i'),
            ],
          ),
        ),
      ),
    );
    expect(controller.offset, 0);
    rotary.feed(2);
    await tester.pump();
    expect(controller.offset, closeTo(96, 0.001));
    rotary.feed(-1);
    await tester.pump();
    expect(controller.offset, closeTo(48, 0.001));
    rotary.feed(-100);
    await tester.pump();
    expect(controller.offset, 0);
  });

  testWidgets('confirm dialog returns true / false', (tester) async {
    bool? result;
    await pumpWear(
      tester,
      wearMaterial(
        Builder(
          builder: (c) => TextButton(
            onPressed: () async =>
                result = await ConfirmDialog.show(c, title: 'Sure?'),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result, true);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, false);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop(); // system swipe-back
    await tester.pumpAndSettle();
    expect(result, false);
  });

  test('SlotRing.slotAt maps angles to slots clockwise from top', () {
    const size = 150.0;
    expect(SlotRing.slotAt(const Offset(75, 5), size, 18), 0);
    expect(SlotRing.slotAt(const Offset(145, 75), size, 18), 2);
    expect(SlotRing.slotAt(const Offset(75, 145), size, 18), 4);
    expect(SlotRing.slotAt(const Offset(5, 75), size, 18), 6);
    expect(SlotRing.slotAt(const Offset(75, 75), size, 18), isNull);
  });

}
