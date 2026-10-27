import 'package:chameleonultragui/wear/input/rotary_controller.dart';
import 'package:chameleonultragui/wear/theme/round_insets.dart';
import 'package:flutter/material.dart';

/// Scrolling column with round-safe padding, rotary scrolling and an optional
/// [header] that scrolls with the content.
class RoundListView extends StatefulWidget {
  const RoundListView({
    super.key,
    required this.children,
    this.header,
    this.controller,
    this.rotary = true,
    this.haptics = true,
  });

  final List<Widget> children;
  final Widget? header;
  final ScrollController? controller;
  final bool rotary;
  final bool haptics;

  @override
  State<RoundListView> createState() => _RoundListViewState();
}

class _RoundListViewState extends State<RoundListView> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      controller: _controller,
      padding: RoundInsets.of(context, hasTitle: widget.header != null),
      children: [if (widget.header != null) widget.header!, ...widget.children],
    );
    if (!widget.rotary) return list;
    return RotaryScrollable(
      controller: _controller,
      haptics: widget.haptics,
      child: list,
    );
  }
}
