import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/wear/connection/ui/connect_screen.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:flutter/widgets.dart';

/// Shows [builder] only while a Chameleon is connected; otherwise shows the
/// connect screen (scan / permissions / connect). Screens that talk to the
/// device wrap their body in this so they never see a null communicator.
///
/// The builder is re-run when the connection changes (a reconnect hands out a
/// new communicator), so do not cache the communicator across builds.
class WearConnectionGate extends StatelessWidget {
  const WearConnectionGate({super.key, required this.builder});

  final Widget Function(BuildContext context, ChameleonCommunicator device)
      builder;

  @override
  Widget build(BuildContext context) {
    final services = WearServicesScope.of(context);
    final connection = services.connection;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final device = connection.communicator;
        if (connection.isConnected && device != null) {
          return builder(context, device);
        }
        return ConnectScreen(connection: connection);
      },
    );
  }
}
