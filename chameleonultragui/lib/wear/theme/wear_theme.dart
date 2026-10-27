import 'package:flutter/material.dart';

/// Design constants for the ~206 dp round watch screen.
class WearMetrics {
  WearMetrics._();

  /// Minimum tap target height (dp).
  static const double minTap = 48;

  /// Highest text scale honoured by the app.
  static const double maxTextScale = 1.3;

  /// Fraction of the short side kept free on each side of scrolling content.
  static const double sideInset = 0.12;

  /// Fraction of the short side kept free above the first / below the last
  /// scrolling item, so content at rest sits inside the circle.
  static const double topInset = 0.17;
  static const double bottomInset = 0.2;
}

class WearColors {
  WearColors._();

  static const Color background = Colors.black;
  static const Color surface = Color(0xFF1B1B1F);
  static const Color primary = Color(0xFF4DD0C4);
  static const Color onPrimary = Color(0xFF00201D);
  static const Color ok = Color(0xFF6FDD8B);
  static const Color warning = Color(0xFFFFB74D);
  static const Color error = Color(0xFFFF6B6B);
  static const Color info = Color(0xFF7FB6FF);
  static const Color muted = Color(0xFF8E9399);
}

class WearTheme {
  WearTheme._();

  static ThemeData build() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: WearColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          surface: WearColors.background,
          primary: WearColors.primary,
          onPrimary: WearColors.onPrimary,
          error: WearColors.error,
          surfaceContainerHighest: WearColors.surface,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: WearColors.background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkRipple.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 16),
        bodyMedium: const TextStyle(fontSize: 15),
        bodySmall: const TextStyle(fontSize: 13, color: WearColors.muted),
        labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(fontSize: 13),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: WearColors.background),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
