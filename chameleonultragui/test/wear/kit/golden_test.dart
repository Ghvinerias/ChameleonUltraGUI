@Tags(['golden'])
library;

import 'dart:io';

import 'package:chameleonultragui/wear/app.dart';
import 'package:chameleonultragui/wear/gallery/widget_gallery.dart';
import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wear_test_harness.dart';

// Image goldens are generated on Linux (`flutter test --update-goldens`);
// font rendering differs on other platforms, so non-Linux CI runs
// `flutter test --exclude-tags golden`.
void main() {
  setUpAll(mockRotaryChannel);
  group('goldens (regenerate on Linux only)', () {
    testWidgets('home menu', (tester) async {
      await pumpWear(tester, const WearApp());
      await expectLater(
        find.byType(WearTestHarness),
        matchesGoldenFile('goldens/home.png'),
      );
    });
    testWidgets('home menu scale 1.3', (tester) async {
      await pumpWear(tester, const WearApp(), textScale: 1.3);
      await expectLater(
        find.byType(WearTestHarness),
        matchesGoldenFile('goldens/home_1_3.png'),
      );
    });
    for (final scale in [1.0, 1.3]) {
      for (final y in [0.0, 600.0, 1100.0]) {
        testWidgets('gallery scale $scale offset $y', (tester) async {
          final c = ScrollController();
          await pumpWear(
            tester,
            wearMaterial(
              RotaryScope(
                controller: RotaryController.fake(),
                child: _GalleryAt(c),
              ),
            ),
            textScale: scale,
          );
          c.jumpTo(y.clamp(0, c.position.maxScrollExtent));
          await tester.pump();
          await expectLater(
            find.byType(WearTestHarness),
            matchesGoldenFile('goldens/gallery_${scale}_${y.toInt()}.png'),
          );
        });
      }
    }
  });

  test('goldens dir exists after update', () {
    // Sanity guard so a missing --update-goldens run is obvious.
    expect(Directory('test/wear/kit/goldens').existsSync(), isTrue);
  });
}

class _GalleryAt extends StatelessWidget {
  const _GalleryAt(this.controller);
  final ScrollController controller;

  @override
  Widget build(BuildContext context) =>
      WidgetGallery(animate: false, controller: controller);
}
