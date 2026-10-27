import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Native rotary-bezel events forwarded by `MainActivity`.
///
/// Measured on the Galaxy Watch 8 Classic (spike G0): Flutter receives no
/// pointer/key events from the bezel; the native channel delivers `double`
/// deltas (about 133 events for a few turns, fractional values, so one
/// physical detent is roughly 0.4-1.0 units). `MainActivity` sends
/// `-AXIS_SCROLL`, i.e. the Android sign is already inverted so that
/// **positive = clockwise = scroll content down (towards the end)**.
/// This matches androidx.wear's rotary scroll convention. The sign has
/// not been re-verified in the UI on hardware by this track.
const rotaryEventChannel = EventChannel('io.chameleon.ultra/rotary');

/// Source of rotary deltas. Production reads [rotaryEventChannel]; tests feed
/// values with [feed].
class RotaryController {
  RotaryController([this._source])
    : _own = StreamController<double>.broadcast();

  /// Controller for tests: only [feed] produces events.
  RotaryController.fake() : this(null);

  /// Shared app-wide controller reading the native channel.
  static final RotaryController shared = RotaryController(_channelStream());

  static Stream<double> _channelStream() => rotaryEventChannel
      .receiveBroadcastStream()
      .where((e) => e is num)
      .map((e) => (e as num).toDouble());

  final Stream<double>? _source;
  final StreamController<double> _own;

  /// Broadcast stream of deltas (positive = clockwise = scroll down).
  Stream<double> get events {
    final src = _source;
    if (src == null) return _own.stream;
    return _merged ??= _mergeStreams(src, _own.stream);
  }

  Stream<double>? _merged;

  static Stream<double> _mergeStreams(Stream<double> a, Stream<double> b) {
    late StreamController<double> c;
    final subs = <StreamSubscription<double>>[];
    c = StreamController<double>.broadcast(
      onListen: () {
        subs.add(a.listen(c.add, onError: (_) {}));
        subs.add(b.listen(c.add));
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
        subs.clear();
      },
    );
    return c.stream;
  }

  /// Inject a fake delta (tests, previews).
  void feed(double delta) => _own.add(delta);
}

/// Provides a non-default [RotaryController] to descendants (tests).
class RotaryScope extends InheritedWidget {
  const RotaryScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final RotaryController controller;

  static RotaryController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RotaryScope>()?.controller ??
      RotaryController.shared;

  @override
  bool updateShouldNotify(RotaryScope old) => controller != old.controller;
}

/// Scrolls [controller] in response to rotary deltas while this route is the
/// current one.
class RotaryScrollable extends StatefulWidget {
  const RotaryScrollable({
    super.key,
    required this.controller,
    required this.child,
    this.pixelsPerUnit = 48,
    this.haptics = true,
  });

  final ScrollController controller;
  final Widget child;

  /// Logical pixels scrolled per unit of rotary delta (about one list tile per
  /// detent at 48 dp).
  final double pixelsPerUnit;
  final bool haptics;

  @override
  State<RotaryScrollable> createState() => _RotaryScrollableState();
}

class _RotaryScrollableState extends State<RotaryScrollable> {
  StreamSubscription<double>? _sub;
  RotaryController? _rotary;
  DateTime _lastHaptic = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = RotaryScope.of(context);
    if (r != _rotary) {
      _sub?.cancel();
      _rotary = r;
      _sub = r.events.listen(_onDelta);
    }
  }

  void _onDelta(double delta) {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final c = widget.controller;
    if (!c.hasClients) return;
    final pos = c.position;
    final target = (pos.pixels + delta * widget.pixelsPerUnit).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if (target == pos.pixels) return;
    c.jumpTo(target);
    if (widget.haptics) {
      final now = DateTime.now();
      if (now.difference(_lastHaptic).inMilliseconds >= 60) {
        _lastHaptic = now;
        HapticFeedback.selectionClick();
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
