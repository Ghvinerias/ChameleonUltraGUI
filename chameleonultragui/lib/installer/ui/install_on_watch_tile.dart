import 'package:flutter/material.dart';

import 'install_wizard_page.dart';
import 'strings.dart';

/// Settings entry (developer mode only) that opens the "Install on watch" wizard.
class InstallOnWatchTile extends StatelessWidget {
  const InstallOnWatchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.watch),
      title: const Text(InstallerStrings.entryTitle),
      subtitle: const Text(InstallerStrings.entrySubtitle),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const InstallWizardPage())),
    );
  }
}
