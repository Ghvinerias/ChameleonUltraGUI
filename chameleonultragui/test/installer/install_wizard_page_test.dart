import 'package:chameleonultragui/installer/ui/install_wizard_page.dart';
import 'package:chameleonultragui/installer/ui/strings.dart';
import 'package:chameleonultragui/installer/watch_installer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_watch_installer.dart';

void main() {
  testWidgets('wizard walks to aftercare with fakes and shows pairing hint', (
    tester,
  ) async {
    final adb = FakeWatchInstaller();
    await tester.pumpWidget(
      MaterialApp(
        home: InstallWizardPage(installer: adb, fetcher: FakeApkFetcher()),
      ),
    );

    await tester.tap(find.text(InstallerStrings.checklistConfirm));
    await tester.pumpAndSettle();

    // pairing failure shows the hint
    adb.pairError = WatchInstallException(
      WatchInstallErrorType.pairingFailed,
      'bad code',
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '192.168.1.5');
    await tester.enterText(fields.at(1), '37625');
    await tester.enterText(fields.at(2), '123456');
    await tester.tap(find.text(InstallerStrings.pairButton));
    await tester.pumpAndSettle();
    expect(
      find.text(
        InstallerStrings.errorTitle(WatchInstallErrorType.pairingFailed),
      ),
      findsOneWidget,
    );

    adb.pairError = null;
    await tester.enterText(find.byType(TextField).at(2), '654321');
    await tester.tap(find.text(InstallerStrings.pairButton));
    await tester.pumpAndSettle();
    expect(find.text(InstallerStrings.connectTitle), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '41593');
    await tester.tap(find.text(InstallerStrings.connectButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(InstallerStrings.downloadButton));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, InstallerStrings.installButton),
    );
    // The fake emits progress through zero-delay timers; pump them explicitly.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(InstallerStrings.launchButton));
    await tester.pumpAndSettle();
    expect(find.text(InstallerStrings.aftercareTitle), findsOneWidget);
    expect(adb.calls, contains('pair 192.168.1.5:37625 654321'));
  });
}
