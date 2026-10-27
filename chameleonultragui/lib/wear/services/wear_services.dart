import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/core/read/read_service_impl.dart';
import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/core/slots/slot_service_impl.dart';
import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/wear/connection/wear_connection.dart';
import 'package:flutter/widgets.dart';

/// Composition root of the watch app: everything feature screens need.
///
/// Feature screens read it with [WearServicesScope.of] and never construct
/// connections, stores or services themselves. Tests build a [WearServices]
/// from fakes (fake serial factory, mocked SharedPreferences) and wrap the
/// screen in a [WearServicesScope].
class WearServices {
  WearServices({required this.prefs, required this.connection});

  final SharedPreferencesProvider prefs;
  final WearConnection connection;

  CardStore get cardStore => prefs.cardStore;
  DictionaryStore get dictionaryStore => prefs.dictionaryStore;

  /// The live communicator, or null when not connected.
  ChameleonCommunicator? get communicator => connection.communicator;

  ReadService? _read;
  SlotService? _slots;
  ChameleonCommunicator? _servicesFor;

  void _refresh() {
    final c = communicator;
    if (c == null) {
      _read = null;
      _slots = null;
      _servicesFor = null;
    } else if (!identical(c, _servicesFor)) {
      // A reconnect creates a new communicator, so services are rebuilt.
      _read = ReadServiceImpl(communicator: c);
      _slots = SlotServiceImpl(c);
      _servicesFor = c;
    }
  }

  /// Read service bound to the current connection (null when disconnected).
  /// The watch never runs hardnested: pass `allowHardnested: false` in the
  /// `HfReadOptions` you hand to it.
  ReadService? get readService {
    _refresh();
    return _read;
  }

  /// Slot service bound to the current connection (null when disconnected).
  SlotService? get slotService {
    _refresh();
    return _slots;
  }
}

/// Provides [WearServices] to the widget tree.
class WearServicesScope extends InheritedWidget {
  const WearServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final WearServices services;

  static WearServices of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<WearServicesScope>();
    assert(scope != null, 'No WearServicesScope above this widget');
    return scope!.services;
  }

  static WearServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WearServicesScope>()?.services;

  @override
  bool updateShouldNotify(WearServicesScope old) => services != old.services;
}
