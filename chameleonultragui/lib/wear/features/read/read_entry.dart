import 'package:chameleonultragui/wear/features/read/read_menu_page.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:flutter/widgets.dart';

/// Entry point of the "Read" destination: the read menu behind the
/// connection gate.
Widget readEntry(BuildContext context) =>
    WearConnectionGate(builder: (_, _) => const ReadMenuPage());
