import 'package:chameleonultragui/wear/features/dictionaries/dictionaries_entry.dart';
import 'package:chameleonultragui/wear/features/device/device_entry.dart';
import 'package:chameleonultragui/wear/features/read/read_entry.dart';
import 'package:chameleonultragui/wear/features/saved_cards/saved_cards_entry.dart';
import 'package:chameleonultragui/wear/features/slots/slots_entry.dart';
import 'package:chameleonultragui/wear/features/sync/sync_entry.dart';
import 'package:chameleonultragui/wear/navigation/diagnostics_entry.dart';
import 'package:chameleonultragui/wear/navigation/wear_destinations.dart';

/// Registers all destination screens. Each feature owns one entry function in
/// `lib/wear/features/<name>/<name>_entry.dart`; this file only wires them and
/// should not need to change when a feature grows.
void registerWearDestinations() {
  WearDestinations.register(WearDestinationId.read, readEntry);
  WearDestinations.register(WearDestinationId.slots, slotsEntry);
  WearDestinations.register(WearDestinationId.savedCards, savedCardsEntry);
  WearDestinations.register(WearDestinationId.dictionaries, dictionariesEntry);
  WearDestinations.register(WearDestinationId.device, deviceEntry);
  WearDestinations.register(WearDestinationId.sync, syncEntry);
  WearDestinations.register(
    WearDestinationId.diagnostics,
    (_) => const DiagnosticsEntry(),
  );
}
