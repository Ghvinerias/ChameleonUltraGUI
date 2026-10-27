import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:flutter/widgets.dart';

/// Round-safe padding derived from the screen size. Flutter reports no safe
/// area on the watch, so layouts must apply this themselves.
class RoundInsets {
  RoundInsets._();

  /// Padding for scrolling lists (extra top/bottom so rest position is safe).
  static EdgeInsets of(BuildContext context, {bool hasTitle = false}) {
    final s = MediaQuery.sizeOf(context).shortestSide;
    return EdgeInsets.fromLTRB(
      s * WearMetrics.sideInset,
      s * (hasTitle ? WearMetrics.topInset * 0.75 : WearMetrics.topInset),
      s * WearMetrics.sideInset,
      s * WearMetrics.bottomInset,
    );
  }

  /// Padding for fixed (non-scrolling) content: central ~80%.
  static EdgeInsets fixed(BuildContext context) {
    final s = MediaQuery.sizeOf(context).shortestSide;
    return EdgeInsets.symmetric(horizontal: s * 0.14, vertical: s * 0.16);
  }
}
