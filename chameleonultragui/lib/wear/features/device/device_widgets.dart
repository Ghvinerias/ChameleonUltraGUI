import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/wear/features/device/device_controller.dart';
import 'package:chameleonultragui/wear/features/device/strings.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Trailing indicator of a setting row: spinner, check, error or chevron.
class SaveBadge extends StatelessWidget {
  const SaveBadge(this.status, {super.key});

  final SaveStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    SaveStatus.saving => const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    SaveStatus.saved => const Icon(
      Icons.check_circle,
      size: 20,
      color: WearColors.ok,
    ),
    SaveStatus.failed => const Icon(
      Icons.error_outline,
      size: 20,
      color: WearColors.error,
    ),
    SaveStatus.idle => const Icon(Icons.chevron_right, size: 20),
  };
}

/// A settings row: label, current value and the save state of that setting.
class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.label,
    required this.value,
    required this.status,
    required this.onTap,
  });

  final String label;
  final String value;
  final SaveStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (status) {
      SaveStatus.saving => '$value · ${DeviceStrings.saving}',
      SaveStatus.saved => '$value · ${DeviceStrings.saved}',
      SaveStatus.failed => '${DeviceStrings.saveFailed}: $value',
      SaveStatus.idle => value,
    };
    return CompactListTile(
      title: label,
      subtitle: subtitle,
      trailing: SaveBadge(status),
      onTap: status == SaveStatus.saving ? null : onTap,
    );
  }
}

/// Pick one of [options]; pops with the choice (null when backed out).
class OptionPickerPage<T> extends StatelessWidget {
  const OptionPickerPage({
    super.key,
    required this.title,
    required this.options,
    required this.labelOf,
    required this.selected,
  });

  final String title;
  final List<T> options;
  final String Function(T) labelOf;
  final T selected;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required String Function(T) labelOf,
    required T selected,
  }) => Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => OptionPickerPage<T>(
        title: title,
        options: options,
        labelOf: labelOf,
        selected: selected,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => RoundScaffold(
    title: title,
    children: [
      for (final o in options)
        CompactListTile(
          title: labelOf(o),
          trailing: o == selected
              ? const Icon(Icons.check, size: 20, color: WearColors.ok)
              : null,
          onTap: () => Navigator.of(context).pop(o),
        ),
    ],
  );
}

/// Minus / plus stepper with an explicit Save, so one change costs one write.
class StepperPage extends StatefulWidget {
  const StepperPage({
    super.key,
    required this.title,
    required this.initial,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
  });

  final String title;
  final int initial;
  final int min;
  final int max;
  final int step;
  final String unit;

  /// Resolves to the saved value, or null when backed out.
  static Future<int?> show(
    BuildContext context, {
    required String title,
    required int initial,
    required int min,
    required int max,
    required int step,
    required String unit,
  }) => Navigator.of(context).push<int>(
    MaterialPageRoute(
      builder: (_) => StepperPage(
        title: title,
        initial: initial,
        min: min,
        max: max,
        step: step,
        unit: unit,
      ),
    ),
  );

  @override
  State<StepperPage> createState() => _StepperPageState();
}

class _StepperPageState extends State<StepperPage> {
  late int _value = widget.initial.clamp(widget.min, widget.max);

  void _move(int delta) =>
      setState(() => _value = (_value + delta).clamp(widget.min, widget.max));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RoundScaffold(
      title: widget.title,
      children: [
        Center(
          child: Text(
            '$_value ${widget.unit}',
            key: const ValueKey('stepper-value'),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              key: const ValueKey('stepper-minus'),
              constraints: const BoxConstraints.tightFor(
                width: WearMetrics.minTap,
                height: WearMetrics.minTap,
              ),
              onPressed: _value > widget.min ? () => _move(-widget.step) : null,
              icon: const Icon(Icons.remove),
            ),
            IconButton.filledTonal(
              key: const ValueKey('stepper-plus'),
              constraints: const BoxConstraints.tightFor(
                width: WearMetrics.minTap,
                height: WearMetrics.minTap,
              ),
              onPressed: _value < widget.max ? () => _move(widget.step) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        WearButton(
          label: DeviceStrings.saveValue,
          onPressed: () => Navigator.of(context).pop(_value),
        ),
      ],
    );
  }
}

/// Numeric keypad for the 6 digit BLE PIN. Validates with the phone's
/// `validateBlePin` rule; pops with the PIN.
class PinEntryPage extends StatefulWidget {
  const PinEntryPage({super.key});

  static Future<String?> show(BuildContext context) => Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => const PinEntryPage()));

  @override
  State<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends State<PinEntryPage> {
  static const _length = 6; // matches the phone's maxLength

  String _pin = '';
  String? _error;

  void _digit(String d) {
    if (_pin.length >= _length) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  void _submit() {
    final error = validateBlePin(_pin, AppLocalizations.of(context)!);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_pin);
  }

  Widget _key(Widget child, VoidCallback? onTap, Key key) => SizedBox(
    width: WearMetrics.minTap,
    height: WearMetrics.minTap,
    child: TextButton(
      key: key,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: WearColors.surface,
        shape: const CircleBorder(),
      ),
      onPressed: onTap,
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = List.generate(
      _length,
      (i) => i < _pin.length ? _pin[i] : '–',
    ).join(' ');
    Widget digit(String d) => _key(
      Text(d, style: theme.textTheme.titleMedium),
      () => _digit(d),
      ValueKey('pin-$d'),
    );
    return RoundScaffold(
      title: DeviceStrings.pinTitle,
      children: [
        Center(
          child: Text(
            shown,
            key: const ValueKey('pin-display'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              key: const ValueKey('pin-error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: WearColors.error,
              ),
            ),
          ),
        const SizedBox(height: 6),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (final d in row) digit(d)],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: WearMetrics.minTap),
              digit('0'),
              _key(
                const Icon(Icons.backspace_outlined, size: 20),
                _back,
                const ValueKey('pin-back'),
              ),
            ],
          ),
        ),
        WearButton(label: DeviceStrings.pinSet, onPressed: _submit),
      ],
    );
  }
}
