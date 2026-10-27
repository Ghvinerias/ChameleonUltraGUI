import 'package:chameleonultragui/wear/spike/spike_controller.dart';
import 'package:chameleonultragui/wear/spike/spike_screens.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const WearApp());
}

class WearApp extends StatefulWidget {
  const WearApp({super.key});

  @override
  State<WearApp> createState() => _WearAppState();
}

class _WearAppState extends State<WearApp> {
  final SpikeController _controller = SpikeController();

  @override
  void initState() {
    super.initState();
    _controller.loadSavedUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.recordFirstFrame();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: SpikeLauncher(controller: _controller),
    );
  }
}
