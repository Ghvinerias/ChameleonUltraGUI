import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/wear/gallery/widget_gallery.dart';
import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:chameleonultragui/wear/navigation/home_page.dart';
import 'package:chameleonultragui/wear/navigation/wear_registrations.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:flutter/material.dart';

/// Root of the watch app: dark OLED theme, clamped text scale, English
/// strings from [AppLocalizations].
class WearApp extends StatelessWidget {
  const WearApp({super.key, this.rotary, this.registerDestinations = true});

  /// Override the rotary source (tests).
  final RotaryController? rotary;

  /// Register the default destinations (diagnostics etc.) on construction.
  final bool registerDestinations;

  @override
  Widget build(BuildContext context) {
    if (registerDestinations) registerWearDestinations();
    final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: WearTheme.build(),
      darkTheme: WearTheme.build(),
      themeMode: ThemeMode.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: WearMetrics.maxTextScale,
        child: child!,
      ),
      home: const _Home(),
    );
    return rotary == null ? app : RotaryScope(controller: rotary!, child: app);
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => WearHomePage(
    extraEntries: [
      CompactListTile(
        key: const ValueKey('home-gallery'),
        title: AppLocalizations.of(context)!.wear_shell_gallery,
        leading: const Icon(Icons.widgets_outlined),
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const WidgetGallery())),
      ),
    ],
  );
}
