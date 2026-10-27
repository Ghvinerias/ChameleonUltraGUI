import 'package:chameleonultragui/wear/features/shared/slot_picker.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wear_test_services.dart';

void main() {
  testWidgets('tap a slot then confirm returns its index', (tester) async {
    final rig = await createWearRig();
    int? result = -1;
    await rig.pump(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async => result = await pickSlot(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SlotRing), findsOneWidget);
    expect(find.text('Tap a slot'), findsOneWidget);

    // Tap the arc at 3 o'clock: slot index 2 (0 at top, clockwise).
    final ring = tester.getRect(find.byType(SlotRing));
    await tester.tapAt(Offset(ring.right - 7, ring.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('Slot 3'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Use slot 3'),
      40,
      scrollable: find.byType(Scrollable).first,
    );
    final btn = find.widgetWithText(WearButton, 'Use slot 3');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.pumpAndSettle();
    await tester.tap(btn, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.byType(SlotPickerPage), findsNothing, reason: 'picker should be closed');
    expect(result, 2);
  });
}
