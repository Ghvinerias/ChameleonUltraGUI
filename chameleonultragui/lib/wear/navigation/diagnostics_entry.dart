import 'package:chameleonultragui/wear/spike/spike_controller.dart';
import 'package:chameleonultragui/wear/spike/spike_screens.dart';
import 'package:flutter/material.dart';

/// Owns a [SpikeController] and shows the existing spike launcher.
class DiagnosticsEntry extends StatefulWidget {
  const DiagnosticsEntry({super.key});

  @override
  State<DiagnosticsEntry> createState() => _DiagnosticsEntryState();
}

class _DiagnosticsEntryState extends State<DiagnosticsEntry> {
  final SpikeController _controller = SpikeController();

  @override
  void initState() {
    super.initState();
    _controller.loadSavedUrl();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SpikeLauncher(controller: _controller);
}
