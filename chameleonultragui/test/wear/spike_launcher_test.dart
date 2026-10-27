import 'dart:io';

import 'package:chameleonultragui/wear/spike/spike_controller.dart';
import 'package:chameleonultragui/wear/spike/spike_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launcher shows all spike entries on a 438x438 screen',
      (tester) async {
    tester.view.physicalSize = const Size(438, 438);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller =
        SpikeController(storageDir: Directory.systemTemp.createTempSync());
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: SpikeLauncher(controller: controller)));

    for (final title in spikeEntryTitles) {
      await tester.scrollUntilVisible(find.text(title), 80,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(title), findsOneWidget);
    }
  });
}
