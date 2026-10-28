import 'dart:async';
import 'dart:math' as math;

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/wear/features/slots/slot_detail_page.dart';
import 'package:chameleonultragui/wear/features/slots/slot_routes.dart';
import 'package:chameleonultragui/wear/features/slots/strings.dart';
import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

bool slotInUse(SlotInfo s) =>
    s.hfType != TagType.unknown || s.lfType != TagType.unknown;

/// Home of the Slots feature: the ring of 8 slots. The bezel moves the focus
/// (its name and tag types show in the middle), tapping a slot opens it.
class SlotsOverviewPage extends StatefulWidget {
  const SlotsOverviewPage({super.key, required this.device});

  final ChameleonCommunicator device;

  @override
  State<SlotsOverviewPage> createState() => _SlotsOverviewPageState();
}

class _SlotsOverviewPageState extends State<SlotsOverviewPage> {
  List<SlotInfo>? _slots;
  int _active = 0;
  int _focus = 0;
  Object? _error;
  bool _loading = false;
  bool _disposed = false;
  StreamSubscription<double>? _rotarySub;
  RotaryController? _rotary;
  double _rotaryAccum = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = RotaryScope.of(context);
    if (r != _rotary) {
      _rotarySub?.cancel();
      _rotary = r;
      _rotarySub = r.events.listen(_onRotary);
    }
    if (_slots == null && _error == null && !_loading) _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _rotarySub?.cancel();
    super.dispose();
  }

  void _onRotary(double delta) {
    if (!mounted || _slots == null) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _rotaryAccum += delta;
    var steps = 0;
    while (_rotaryAccum >= 1) {
      steps++;
      _rotaryAccum -= 1;
    }
    while (_rotaryAccum <= -1) {
      steps--;
      _rotaryAccum += 1;
    }
    if (steps == 0) return;
    // Dart's % is never negative for a positive divisor.
    setState(() => _focus = (_focus + steps) % SlotRing.slotCount);
  }

  Future<void> _load() async {
    final service = WearServicesScope.of(context).slotService;
    if (service == null) {
      setState(() => _error = 'not connected');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slots = await service.getSlots();
      final active = await service.getActiveSlot();
      if (_disposed) return;
      setState(() {
        _slots = slots;
        _active = active;
        _loading = false;
      });
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _open(int index) async {
    final slots = _slots;
    if (slots == null) return;
    setState(() => _focus = index);
    await pushDevicePage<void>(
      context,
      (context, device) => SlotDetailPage(
        device: device,
        slot: slots[index],
        isActive: _active == index,
      ),
    );
    if (!_disposed) {
      _slots = null;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    if (_error != null) {
      return RoundScaffold(
        title: SlotStrings.title,
        children: [
          Text(
            SlotStrings.loadFailed,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            SlotStrings.failed(_error!),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          WearButton(label: SlotStrings.retry, onPressed: _load),
        ],
      );
    }
    if (slots == null) {
      return const RoundScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final states = [
      for (final s in slots)
        s.index == _active
            ? SlotState.active
            : slotInUse(s)
            ? SlotState.used
            : SlotState.empty,
    ];
    final size = math.min(
      MediaQuery.sizeOf(context).shortestSide * 0.78,
      180.0,
    );
    const stroke = 14.0;
    return RoundScaffold(
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            SlotRing(
              states: states,
              size: size,
              strokeWidth: stroke,
              onSlotTap: _open,
              child: _FocusSummary(
                slot: slots[_focus],
                isActive: slots[_focus].index == _active,
                onTap: () => _open(_focus),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                size: Size.square(size),
                painter: _FocusMarkerPainter(
                  _focus,
                  stroke,
                  Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusSummary extends StatelessWidget {
  const _FocusSummary({
    required this.slot,
    required this.isActive,
    required this.onTap,
  });

  final SlotInfo slot;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = slotInUse(slot);
    final name = slot.hfName.isNotEmpty ? slot.hfName : slot.lfName;
    final types = [
      if (slot.hfType != TagType.unknown)
        '${SlotStrings.hf} ${SlotStrings.tagLabel(slot.hfType)}',
      if (slot.lfType != TagType.unknown)
        '${SlotStrings.lf} ${SlotStrings.tagLabel(slot.lfType)}',
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                SlotStrings.slot(slot.index),
                style: theme.textTheme.labelLarge,
              ),
              if (isActive)
                Text(
                  SlotStrings.active,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              Text(
                used
                    ? (name.isEmpty ? SlotStrings.inUse : name)
                    : SlotStrings.empty,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              for (final t in types)
                Text(
                  t,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small dot just inside the focused segment of the ring.
class _FocusMarkerPainter extends CustomPainter {
  _FocusMarkerPainter(this.focus, this.stroke, this.color);

  final int focus;
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const sweep = 2 * math.pi / SlotRing.slotCount;
    final angle = -math.pi / 2 + (focus + 0.5) * sweep;
    final r = size.width / 2 - stroke - 5;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      c + Offset(math.cos(angle), math.sin(angle)) * r,
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_FocusMarkerPainter old) =>
      old.focus != focus || old.color != color || old.stroke != stroke;
}
