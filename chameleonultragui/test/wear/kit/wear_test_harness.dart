import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Watch screen: 438x438 px at DPR 2.125 (~206 dp), round.
const wearPixels = Size(438, 438);
const wearDpr = 2.125;

/// Clips [child] to a circle, as the real display does.
class WearTestHarness extends StatelessWidget {
  const WearTestHarness({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: ClipOval(child: child),
  );
}

/// A MaterialApp configured like [WearApp] hosting [page].
Widget wearMaterial(Widget page) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: WearTheme.build(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: const [Locale('en')],
  locale: const Locale('en'),
  builder: (context, child) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: WearMetrics.maxTextScale,
    child: child!,
  ),
  home: page,
);

/// Sets the surface to the watch screen and the text scale, then pumps
/// [app] (a full MaterialApp such as WearApp or [wearMaterial]) in the clip.
Future<void> pumpWear(
  WidgetTester tester,
  Widget app, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = wearPixels;
  tester.view.devicePixelRatio = wearDpr;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(WearTestHarness(child: app));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Stubs the native rotary EventChannel (no host in unit tests).
void mockRotaryChannel() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('io.chameleon.ultra/rotary'),
        (call) async => null,
      );
  // keep the const channel referenced so a rename breaks this stub loudly
  assert(rotaryEventChannel.name == 'io.chameleon.ultra/rotary');
}
