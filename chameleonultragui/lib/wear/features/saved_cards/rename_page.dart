import 'package:chameleonultragui/wear/features/saved_cards/strings.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Text entry for a new card name (system keyboard / voice input). Pops with
/// the trimmed name, or null when cancelled.
class RenameCardPage extends StatefulWidget {
  const RenameCardPage({super.key, required this.initialName});

  final String initialName;

  @override
  State<RenameCardPage> createState() => _RenameCardPageState();
}

class _RenameCardPageState extends State<RenameCardPage> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _text.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => RoundScaffold(
    title: SavedCardsStrings.renameTitle,
    children: [
      TextField(
        controller: _text,
        maxLength: 64,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: SavedCardsStrings.nameHint,
          counterText: '',
        ),
      ),
      const SizedBox(height: 6),
      WearButton(
        label: SavedCardsStrings.save,
        onPressed: _text.text.trim().isEmpty ? null : _submit,
      ),
    ],
  );
}
