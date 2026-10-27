import 'dart:async';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/wear/spike/report_qr.dart';
import 'package:chameleonultragui/wear/spike/spike_controller.dart';
import 'package:chameleonultragui/wear/spike/spike_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Titles of the launcher entries (also used by tests).
const spikeEntryTitles = [
  'Device info',
  'Rotary / bezel',
  'BLE + Chameleon',
  'Native recovery',
  'Storage timing',
  'Network',
  'Report',
];

/// Round-safe page: content lives in the central ~80% and scrolls.
class RoundPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const RoundPage({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListView(
        padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).shortestSide * 0.1,
            vertical: MediaQuery.sizeOf(context).shortestSide * 0.14),
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.tealAccent)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const BigButton(this.label, this.onPressed, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28))),
          onPressed: onPressed,
          child: Text(label,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ),
      );
}

class SpikeLauncher extends StatelessWidget {
  final SpikeController controller;

  const SpikeLauncher({super.key, required this.controller});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DeviceInfoPage(controller: controller),
      RotaryPage(controller: controller),
      BlePage(controller: controller),
      RecoveryPage(controller: controller),
      StoragePage(controller: controller),
      NetworkPage(controller: controller),
      ReportPage(controller: controller),
    ];
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RoundPage(
        title: 'Spike G0',
        children: [
          if (controller.previousHardnestedUnfinished)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Previous run did not finish hardnested',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 14)),
            ),
          for (var i = 0; i < pages.length; i++)
            BigButton(spikeEntryTitles[i], () => _open(context, pages[i])),
        ],
      ),
    );
  }
}

/// Shared scaffold for a test page: buttons + status + latest results.
class _TestPage extends StatelessWidget {
  final SpikeController controller;
  final String title;
  final List<Widget> Function(BuildContext) buttons;
  final List<String> resultPrefixes;

  const _TestPage(
      {required this.controller,
      required this.title,
      required this.buttons,
      required this.resultPrefixes});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final results = controller.report.results.where(
            (r) => resultPrefixes.any((p) => r.name.startsWith(p)));
        return RoundPage(title: title, children: [
          ...buttons(context),
          if (controller.busy)
            const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator())),
          if (controller.status.isNotEmpty)
            Text(controller.status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          for (final r in results) ResultTile(r),
        ]);
      },
    );
  }
}

class ResultTile extends StatelessWidget {
  final SpikeResult result;

  const ResultTile(this.result, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = switch (result.status) {
      SpikeStatus.ok => Colors.greenAccent,
      SpikeStatus.fail => Colors.redAccent,
      SpikeStatus.skipped => Colors.grey,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '${result.status.name.toUpperCase()} ${result.name} '
                '(${result.durationMs} ms)\n',
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        TextSpan(text: result.details),
      ]), style: const TextStyle(fontSize: 13, color: Colors.white)),
    );
  }
}

class DeviceInfoPage extends StatelessWidget {
  final SpikeController controller;

  const DeviceInfoPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => _TestPage(
        controller: controller,
        title: 'Device info',
        resultPrefixes: const ['device_info'],
        buttons: (ctx) => [
          BigButton('Collect', () => controller.deviceInfo(MediaQuery.of(ctx))),
        ],
      );
}

class RotaryPage extends StatefulWidget {
  final SpikeController controller;

  const RotaryPage({super.key, required this.controller});

  @override
  State<RotaryPage> createState() => _RotaryPageState();
}

class _RotaryPageState extends State<RotaryPage> {
  final _focus = FocusNode();
  StreamSubscription<dynamic>? _native;

  @override
  void initState() {
    super.initState();
    // Native path: MainActivity forwards SOURCE_ROTARY_ENCODER scroll events,
    // because Flutter ignores non-pointer sources.
    _native = rotaryChannel.receiveBroadcastStream().listen(
        (d) => widget.controller.onNativeRotary((d as num).toDouble()),
        onError: (_) {});
  }

  @override
  void dispose() {
    _native?.cancel();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    widget.controller.onKey(
        '${e.runtimeType} logical=${e.logicalKey.debugName} '
        'physical=${e.physicalKey.debugName} char=${e.character}');
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            c.onScroll('delta=${e.scrollDelta} kind=${e.kind} device=${e.device}');
          } else {
            c.onScroll('signal ${e.runtimeType}');
          }
        },
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => RoundPage(
            title: 'Rotate the bezel',
            children: [
              Text('scroll events: ${c.scrollEvents}',
                  style: const TextStyle(fontSize: 18, color: Colors.white)),
              Text('key events: ${c.keyEvents}',
                  style: const TextStyle(fontSize: 18, color: Colors.white)),
              Text('native rotary: ${c.nativeRotaryEvents} (sum ${c.nativeRotaryTotal.toStringAsFixed(1)})',
                  style: const TextStyle(fontSize: 18, color: Colors.white)),
              const SizedBox(height: 6),
              Text('last scroll: ${c.lastScroll}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Text('last key: ${c.lastKey}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              BigButton('Save result', c.saveRotary),
              BigButton('Reset counters', c.resetRotary),
            ],
          ),
        ),
      ),
    );
  }
}

class BlePage extends StatelessWidget {
  final SpikeController controller;

  const BlePage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _TestPage(
      controller: c,
      title: 'BLE + Chameleon',
      resultPrefixes: const ['ble_', 'chameleon_'],
      buttons: (ctx) => [
        BigButton('1. Permissions + scan', c.busy ? null : c.bleScan),
        for (final d in c.found)
          BigButton('2. Connect ${chameleonDeviceName(d.device)}${d.dfu ? " DFU" : ""}',
              c.busy ? null : () => c.bleConnectAndQuery(d)),
        BigButton('3. Start 90 s keep-alive test',
            c.busy || c.communicator == null ? null : c.keepAliveTest),
        if (c.keepAliveProgress.isNotEmpty)
          Text('keep-alive: ${c.keepAliveProgress}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        BigButton('Disconnect', c.bleDisconnect),
      ],
    );
  }
}

class RecoveryPage extends StatelessWidget {
  final SpikeController controller;

  const RecoveryPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _TestPage(
      controller: c,
      title: 'Native recovery',
      resultPrefixes: const ['recovery_'],
      buttons: (ctx) => [
        BigButton('1. Load + darkside/nested', c.busy ? null : c.recoveryChecks),
        BigButton('2. Hardnested (LAST, up to 120 s)',
            c.busy ? null : c.hardnestedCheck),
      ],
    );
  }
}

class StoragePage extends StatelessWidget {
  final SpikeController controller;

  const StoragePage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => _TestPage(
        controller: controller,
        title: 'Storage timing',
        resultPrefixes: const ['storage_'],
        buttons: (ctx) => [
          BigButton('Run (writes 5 MB temp)',
              controller.busy ? null : controller.storageChecks),
        ],
      );
}

class NetworkPage extends StatelessWidget {
  final SpikeController controller;

  const NetworkPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => _TestPage(
        controller: controller,
        title: 'Network',
        resultPrefixes: const ['network'],
        buttons: (ctx) => [
          Text(controller.reportUrl,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          BigButton('GET /health', controller.busy ? null : controller.networkCheck),
        ],
      );
}

class ReportPage extends StatefulWidget {
  final SpikeController controller;

  const ReportPage({super.key, required this.controller});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late final TextEditingController _url =
      TextEditingController(text: widget.controller.reportUrl);

  @override
  void initState() {
    super.initState();
    widget.controller.loadSavedUrl().then((_) {
      if (mounted) _url.text = widget.controller.reportUrl;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => RoundPage(title: 'Report', children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Receiver URL'),
          onChanged: c.setReportUrl,
        ),
        BigButton('Show report as QR', () {
          c.finalizeReportNotes();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReportQrPage(report: c.report.toJson())));
        }),
        BigButton('Send report', c.busy ? null : c.sendReport),
        BigButton('Reset URL', () {
          _url.text = defaultReportUrl;
          c.setReportUrl(defaultReportUrl);
        }),
        if (c.status.isNotEmpty)
          Text(c.status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(c.report.summary(),
            style: const TextStyle(fontSize: 12, color: Colors.white)),
      ]),
    );
  }
}

/// Shows the report as a short series of QR codes (no network needed).
class ReportQrPage extends StatefulWidget {
  final Map<String, dynamic> report;

  const ReportQrPage({super.key, required this.report});

  @override
  State<ReportQrPage> createState() => _ReportQrPageState();
}

class _ReportQrPageState extends State<ReportQrPage> {
  late final List<String> frames = encodeReportForQr(widget.report);
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide * 0.72;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('QR ${index + 1} / ${frames.length}  id ${reportQrId(frames)}',
                style: const TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            QrImageView(
              data: frames[index],
              version: QrVersions.auto,
              size: side,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(8),
              errorCorrectionLevel: QrErrorCorrectLevel.L,
            ),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  onPressed:
                      index > 0 ? () => setState(() => index--) : null,
                  icon: const Icon(Icons.chevron_left)),
              IconButton(
                  onPressed: index < frames.length - 1
                      ? () => setState(() => index++)
                      : null,
                  icon: const Icon(Icons.chevron_right)),
            ]),
          ],
        ),
      ),
    );
  }
}
