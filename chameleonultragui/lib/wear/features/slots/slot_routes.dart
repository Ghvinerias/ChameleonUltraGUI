import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:flutter/material.dart';

/// Pushes a page that talks to the device. The page sits behind its own
/// connection gate so a dropped link shows the connect screen instead of
/// failing every command; a reconnect rebuilds the page with the new device.
Future<T?> pushDevicePage<T>(
  BuildContext context,
  Widget Function(BuildContext context, ChameleonCommunicator device) builder,
) => Navigator.of(context).push<T>(
  MaterialPageRoute(
    builder: (_) => WearConnectionGate(
      builder: (context, device) =>
          KeyedSubtree(key: ValueKey(device), child: builder(context, device)),
    ),
  ),
);
