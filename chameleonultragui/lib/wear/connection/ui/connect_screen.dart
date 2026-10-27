import 'package:chameleonultragui/wear/connection/wear_connection.dart';
import 'package:flutter/material.dart';

/// Plain functional connect screen for a ~206 dp round display. A later track
/// restyles it with the T2 kit.
class ConnectScreen extends StatefulWidget {
  final WearConnection connection;

  /// Run `autoConnect()` when the screen opens.
  final bool autoStart;

  /// Called once when the state becomes `connected`.
  final VoidCallback? onConnected;

  const ConnectScreen({
    super.key,
    required this.connection,
    this.autoStart = true,
    this.onConnected,
  });

  static String errorText(WearConnectionError e) => switch (e) {
    WearConnectionError.none => '',
    WearConnectionError.permissionDenied => 'Bluetooth permission is required',
    WearConnectionError.permissionPermanentlyDenied =>
      'Permission blocked. Enable it in settings',
    WearConnectionError.scanFailed => 'Scan failed. Is Bluetooth on?',
    WearConnectionError.noDeviceFound => 'No Chameleon found',
    WearConnectionError.dfuDevice => 'Device is in DFU mode',
    WearConnectionError.connectFailed => 'Could not connect',
    WearConnectionError.connectionLost => 'Connection lost',
  };

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _notified = false;

  WearConnection get c => widget.connection;

  @override
  void initState() {
    super.initState();
    c.addListener(_check);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.autoConnect();
      });
    }
  }

  @override
  void dispose() {
    c.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (c.isConnected && !_notified) {
      _notified = true;
      widget.onConnected?.call();
    } else if (!c.isConnected) {
      _notified = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Center(
            child: SingleChildScrollView(
              // keep content inside the circle
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _content(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback? onTap) => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton(onPressed: onTap, child: Text(label)),
  );

  Widget _text(String s, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      s,
      textAlign: TextAlign.center,
      style: TextStyle(color: color ?? Colors.white, fontSize: 15),
    ),
  );

  List<Widget> _content(BuildContext context) {
    final err = ConnectScreen.errorText(c.lastError);
    switch (c.state) {
      case WearConnectionState.scanning:
        return [const CircularProgressIndicator(), _text('Scanning...')];
      case WearConnectionState.connecting:
        return [const CircularProgressIndicator(), _text('Connecting...')];
      case WearConnectionState.reconnecting:
        return [
          const CircularProgressIndicator(),
          _text('Reconnecting (${c.reconnectAttempt})...'),
          _button('Cancel', () => c.disconnect()),
        ];
      case WearConnectionState.connected:
        return [
          const Icon(Icons.bluetooth_connected, color: Colors.lightBlue),
          _text('Connected\n${c.activeDevice?.name ?? ''}'),
          _button('Disconnect', () => c.disconnect()),
        ];
      case WearConnectionState.permissionNeeded:
        final blocked =
            c.lastError == WearConnectionError.permissionPermanentlyDenied;
        return [
          _text(err, color: Colors.orangeAccent),
          _button(
            blocked ? 'Open settings' : 'Allow',
            blocked ? c.openPermissionSettings : c.scan,
          ),
        ];
      case WearConnectionState.devicesFound:
        return [
          for (final d in c.devices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: _button(d.name, () => c.connect(d)),
            ),
          for (final d in c.dfuDevices) _text(d.name, color: Colors.grey),
          _button('Rescan', c.scan),
        ];
      case WearConnectionState.idle:
      case WearConnectionState.failed:
        return [
          if (err.isNotEmpty) _text(err, color: Colors.orangeAccent),
          _button('Scan', c.scan),
        ];
    }
  }
}
