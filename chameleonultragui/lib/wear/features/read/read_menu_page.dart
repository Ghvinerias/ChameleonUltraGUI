import 'package:chameleonultragui/wear/features/read/read_controller.dart';
import 'package:chameleonultragui/wear/features/read/read_effects.dart';
import 'package:chameleonultragui/wear/features/read/read_page.dart';
import 'package:chameleonultragui/wear/features/read/strings.dart';
import 'package:chameleonultragui/wear/services/connection_gate.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:flutter/material.dart';

/// "Read" menu: single and continuous HF / LF reads.
class ReadMenuPage extends StatelessWidget {
  const ReadMenuPage({
    super.key,
    this.effects = const ReadEffects(),
    this.animate = true,
  });

  final ReadEffects effects;
  final bool animate;

  void _open(BuildContext context, ReadMode mode) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WearConnectionGate(
          builder: (_, _) =>
              ReadPage(mode: mode, effects: effects, animate: animate),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RoundScaffold(
    title: ReadStrings.menuTitle,
    children: [
      CompactListTile(
        title: ReadStrings.readHf,
        leading: const Icon(Icons.nfc),
        onTap: () => _open(context, ReadMode.hf),
      ),
      CompactListTile(
        title: ReadStrings.readLf,
        leading: const Icon(Icons.contactless),
        onTap: () => _open(context, ReadMode.lf),
      ),
      CompactListTile(
        title: ReadStrings.scanHf,
        leading: const Icon(Icons.radar),
        onTap: () => _open(context, ReadMode.scanHf),
      ),
      CompactListTile(
        title: ReadStrings.scanLf,
        leading: const Icon(Icons.radar),
        onTap: () => _open(context, ReadMode.scanLf),
      ),
    ],
  );
}
