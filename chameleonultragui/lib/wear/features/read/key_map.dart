import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:flutter/material.dart';

/// Compact per-sector key map of a Mifare Classic card: one cell per sector,
/// key A on top and key B below. Green = found, amber = being checked, grey =
/// not tried yet, red outline = still missing ([showMissing]), dark = n/a.
class SectorKeyMap extends StatelessWidget {
  const SectorKeyMap({
    super.key,
    required this.states,
    required this.sectors,
    this.showMissing = false,
    this.width = 144,
  });

  /// Length 80 (sector * 2 + keyType) as in `MifareClassicReadState`.
  final List<SectorKeyState> states;
  final int sectors;
  final bool showMissing;
  final double width;

  static const columns = 8;
  static const cellHeight = 20.0;

  /// Number of found keys among the [sectors] sectors.
  static int foundCount(List<SectorKeyState> states, int sectors) {
    var n = 0;
    for (var i = 0; i < sectors * 2 && i < states.length; i++) {
      if (states[i] == SectorKeyState.found) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final rows = (sectors / columns).ceil();
    final found = foundCount(states, sectors);
    return Semantics(
      label: 'Keys found: $found of ${sectors * 2}',
      child: ExcludeSemantics(
        child: Center(
          child: CustomPaint(
            size: Size(width, rows * cellHeight),
            painter: _KeyMapPainter(List.of(states), sectors, showMissing),
          ),
        ),
      ),
    );
  }
}

class _KeyMapPainter extends CustomPainter {
  _KeyMapPainter(this.states, this.sectors, this.showMissing);

  final List<SectorKeyState> states;
  final int sectors;
  final bool showMissing;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / SectorKeyMap.columns;
    for (var s = 0; s < sectors; s++) {
      final col = s % SectorKeyMap.columns;
      final row = s ~/ SectorKeyMap.columns;
      for (var k = 0; k < 2; k++) {
        final idx = s * 2 + k;
        final state = idx < states.length ? states[idx] : SectorKeyState.none;
        final rect = Rect.fromLTWH(
          col * cellW + 2,
          row * SectorKeyMap.cellHeight + k * 9 + 1,
          cellW - 4,
          7,
        );
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        switch (state) {
          case SectorKeyState.found:
            canvas.drawRRect(rrect, Paint()..color = WearColors.ok);
          case SectorKeyState.checking:
            canvas.drawRRect(rrect, Paint()..color = WearColors.warning);
          case SectorKeyState.disabled:
            canvas.drawRRect(rrect, Paint()..color = WearColors.surface);
          case SectorKeyState.none:
            if (showMissing) {
              canvas.drawRRect(
                rrect,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5
                  ..color = WearColors.error,
              );
            } else {
              canvas.drawRRect(rrect, Paint()..color = WearColors.muted);
            }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_KeyMapPainter old) =>
      old.sectors != sectors ||
      old.showMissing != showMissing ||
      !_same(old.states, states);

  static bool _same(List<SectorKeyState> a, List<SectorKeyState> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
