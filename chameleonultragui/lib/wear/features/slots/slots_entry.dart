import 'package:chameleonultragui/wear/features/slots/slots_overview_page.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:flutter/widgets.dart';

/// Entry point of the "Slots" destination: the 8-slot overview, behind the
/// connection gate.
Widget slotsEntry(BuildContext context) => WearConnectionGate(
  builder: (context, device) =>
      SlotsOverviewPage(key: ValueKey(device), device: device),
);
