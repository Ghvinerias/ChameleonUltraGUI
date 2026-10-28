import 'dart:convert';

import 'package:chameleonultragui/wear/features/slots/strings.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';

/// Max slot nickname length on the device, in UTF-8 bytes.
const int kSlotNameMaxBytes = 32;

/// Asks for a new slot name; pops with the trimmed text, or null on back.
class SlotRenamePage extends StatefulWidget {
  const SlotRenamePage({super.key, required this.title, this.initial = ''});

  final String title;
  final String initial;

  @override
  State<SlotRenamePage> createState() => _SlotRenamePageState();
}

class _SlotRenamePageState extends State<SlotRenamePage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final t = _controller.text.trim();
    return t.isNotEmpty && utf8.encode(t).length <= kSlotNameMaxBytes;
  }

  @override
  Widget build(BuildContext context) {
    return RoundScaffold(
      title: widget.title,
      children: [
        TextField(
          controller: _controller,
          autofocus: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_valid) Navigator.of(context).pop(_controller.text.trim());
          },
          decoration: const InputDecoration(labelText: SlotStrings.nameLabel),
        ),
        WearButton(
          label: SlotStrings.save,
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
        ),
      ],
    );
  }
}
