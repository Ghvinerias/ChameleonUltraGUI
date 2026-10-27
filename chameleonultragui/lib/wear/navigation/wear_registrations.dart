import 'package:chameleonultragui/wear/navigation/diagnostics_entry.dart';
import 'package:chameleonultragui/wear/navigation/wear_destinations.dart';

/// Registers all destination screens. Feature tracks append one line here
/// (or call [WearDestinations.register] from their own startup code).
void registerWearDestinations() {
  WearDestinations.register(
    WearDestinationId.diagnostics,
    (_) => const DiagnosticsEntry(),
  );
}
