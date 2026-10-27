import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wear_test_services.dart';

void main() {
  testWidgets('services expose the connected fake and rebuild per connection', (
    tester,
  ) async {
    final rig = await createWearRig();
    expect(rig.services.communicator, same(rig.fake));
    expect(rig.services.readService, isNotNull);
    expect(rig.services.slotService, isNotNull);
    expect(rig.services.cardStore, same(rig.prefs.cardStore));
    final first = rig.services.readService;
    expect(rig.services.readService, same(first));
  });

  testWidgets('gate shows the child when connected', (tester) async {
    final rig = await createWearRig();
    await rig.pump(
      tester,
      WearConnectionGate(builder: (_, device) => const Text('CONNECTED')),
    );
    expect(find.text('CONNECTED'), findsOneWidget);
  });

  testWidgets('gate shows the connect screen when idle', (tester) async {
    final rig = await createWearRig(connected: false);
    expect(rig.services.readService, isNull);
    await rig.pump(
      tester,
      WearConnectionGate(builder: (_, device) => const Text('CONNECTED')),
    );
    expect(find.text('CONNECTED'), findsNothing);
    expect(WearServicesScope.maybeOf(tester.element(find.byType(Scaffold).first)),
        isNotNull);
  });
}
