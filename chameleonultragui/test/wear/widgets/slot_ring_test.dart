import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ring asked to be 160 dp but the parent only offers 100 dp (the safe square
  // on the watch is smaller than the ring was designed for): taps must still
  // land on the segment that is drawn there.
  testWidgets('taps hit the drawn segment when the ring is squeezed', (
    tester,
  ) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: SlotRing(
              states: List.filled(SlotRing.slotCount, SlotState.used),
              size: 160,
              strokeWidth: 14,
              onSlotTap: tapped.add,
            ),
          ),
        ),
      ),
    );
    final box = tester.getTopLeft(find.byType(SlotRing));
    // Bottom, a little right of centre: slot index 3 of 8 (clockwise from top).
    await tester.tapAt(box + const Offset(66, 89));
    // Top right: index 0.
    await tester.tapAt(box + const Offset(62, 10));
    // Left: index 5/6 boundary region, just check it reports something.
    await tester.tapAt(box + const Offset(10, 50));
    expect(tapped.take(2), [3, 0]);
    expect(tapped.length, 3);
  });
}
