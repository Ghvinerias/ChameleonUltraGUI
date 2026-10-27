import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/confirm_dialog.dart';
import 'package:chameleonultragui/wear/widgets/progress_ring.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/scan_pulse.dart';
import 'package:chameleonultragui/wear/widgets/slot_ring.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Demo page showing every kit widget. [animate] false freezes animations
/// (golden tests).
class WidgetGallery extends StatelessWidget {
  const WidgetGallery({super.key, this.animate = true, this.controller});

  final bool animate;
  final ScrollController? controller;

  Widget _section(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      t,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelMedium,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return RoundScaffold(
      title: l.wear_shell_gallery,
      controller: controller,
      children: [
        _section(context, 'CompactListTile'),
        const CompactListTile(
          title: 'Mifare Classic 1K',
          subtitle: 'UID 01 02 03 04',
          leading: Icon(Icons.nfc),
        ),
        CompactListTile(
          title: 'Tap me',
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
        _section(context, 'WearButton'),
        WearButton(label: 'Filled', icon: Icons.play_arrow, onPressed: () {}),
        WearButton(
          label: 'Tonal',
          style: WearButtonStyle.tonal,
          onPressed: () {},
        ),
        WearButton(
          label: 'Delete',
          style: WearButtonStyle.destructive,
          onPressed: () {},
        ),
        WearButton(
          label: 'Confirm dialog',
          style: WearButtonStyle.tonal,
          onPressed: () => ConfirmDialog.show(
            context,
            title: 'Delete card?',
            message: 'This cannot be undone.',
            destructive: true,
          ),
        ),
        _section(context, 'StatusPill'),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            StatusPill(label: 'OK', kind: StatusKind.ok, icon: Icons.check),
            StatusPill(label: 'Warn', kind: StatusKind.warning),
            StatusPill(label: 'Error', kind: StatusKind.error),
            StatusPill(label: 'Info', kind: StatusKind.info),
          ],
        ),
        _section(context, 'ProgressRing'),
        const Center(child: ProgressRing(value: 0.65, child: Text('65%'))),
        _section(context, 'ScanPulse'),
        Center(child: ScanPulse(animate: animate)),
        _section(context, 'SlotRing'),
        Center(
          child: SlotRing(
            states: const [
              SlotState.active,
              SlotState.used,
              SlotState.used,
              SlotState.empty,
              SlotState.used,
              SlotState.empty,
              SlotState.empty,
              SlotState.empty,
            ],
            onSlotTap: (_) {},
            child: const Text('1/8'),
          ),
        ),
      ],
    );
  }
}
