import 'dart:typed_data';

import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/wear/features/read/read_effects.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../kit/wear_test_harness.dart';

/// Records keep-awake toggles and haptics instead of calling plugins.
class RecordingEffects {
  final List<bool> awake = [];
  int haptics = 0;

  ReadEffects get effects => ReadEffects(
    setKeepAwake: (on) async => awake.add(on),
    hapticFound: () async => haptics++,
  );
}

/// [WearServices] with a custom [ReadService] (to inject a key recovery
/// backend); everything else comes from [base].
class ServicesWithRead extends WearServices {
  ServicesWithRead(WearServices base, this._read)
    : super(prefs: base.prefs, connection: base.connection);

  final ReadService _read;

  @override
  ReadService? get readService => _read;
}

/// Pumps [screen] on the watch surface inside [services].
Future<void> pumpWithServices(
  WidgetTester tester,
  WearServices services,
  Widget screen, {
  double textScale = 1.0,
}) async {
  mockRotaryChannel();
  await pumpWear(
    tester,
    WearServicesScope(services: services, child: wearMaterial(screen)),
    textScale: textScale,
  );
}

/// Pumps in small steps until [finder] matches (animations never settle on
/// the scan screens, so `pumpAndSettle` is not usable). The list is lazy, so
/// when the widget is not built after the wait it scrolls down to look.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxMs = 10000,
}) async {
  for (var ms = 0; ms < maxMs && finder.evaluate().isEmpty; ms += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (finder.evaluate().isEmpty &&
      find.byType(Scrollable).evaluate().isNotEmpty) {
    try {
      await tester.scrollUntilVisible(
        finder,
        60,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
    } catch (_) {}
    await pumpFor(tester, const Duration(seconds: 1));
  }
  expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
}

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  for (var ms = 0; ms < d.inMilliseconds; ms += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls to the [WearButton] labelled [label] and taps it.
Future<void> tapButton(WidgetTester tester, String label) async {
  final f = find.widgetWithText(WearButton, label);
  await tester.scrollUntilVisible(
    f,
    60,
    scrollable: find.byType(Scrollable).first,
  );
  await pumpFor(tester, const Duration(seconds: 1)); // let the fling end
  await tester.tap(f);
  await tester.pump();
}

Uint8List bytes(List<int> v) => Uint8List.fromList(v);
