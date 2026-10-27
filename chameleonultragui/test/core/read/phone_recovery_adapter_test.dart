// MifareClassicRecovery must keep rendering key recovery progress with the
// app's localized strings while the work happens in the headless engine.
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_card.dart';
import 'fake_key_recovery_backend.dart';
import 'phone_harness.dart';
import 'recovery_fake.dart';

void main() {
  testWidgets('recoverKeys shows localized nested progress and finishes', (
    tester,
  ) async {
    final card = FakeCard.mfc1kCustomKey();
    final comm = RecoveryFake([card]);
    late BuildContext ctx;
    await pumpPhoneApp(
      tester,
      comm,
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    );
    final l10n = AppLocalizations.of(ctx)!;
    final key = card.keyA[1].fold<int>(0, (acc, b) => (acc << 8) | b);
    final backend = FakeKeyRecoveryBackend(
      results: {
        'nested': [key],
      },
    );

    final (_, mfc, _) = await readHFInfo(ctx, () {});
    final old = mfc.recovery!;
    final recovery = MifareClassicRecovery(
      appState: old.appState,
      update: () {},
      localizations: l10n,
      mifareClassicType: old.mifareClassicType,
      backend: backend,
    );
    recovery.selectedDictionary = Dictionary(id: '', name: 'e', keys: []);
    await recovery.checkKeys();
    expect(recovery.allKeysExists, isFalse);

    final seen = <String>[];
    recovery.update = () {
      if (seen.isEmpty || seen.last != recovery.state) seen.add(recovery.state);
    };
    await recovery.recoverKeys();

    expect(recovery.error, '');
    expect(recovery.allKeysExists, isTrue);
    expect(recovery.state, '');
    expect(recovery.checkMarks[1], ChameleonKeyCheckmark.found);
    expect(seen, contains(l10n.checking_card_info));
    expect(seen, contains(l10n.collecting_nonces('Nested')));
    expect(seen, contains(l10n.recovering_key('Nested')));
    expect(backend.calls, ['nested']);
  });

  testWidgets('no usable key sets the localized darkside error', (
    tester,
  ) async {
    final comm = RecoveryFake([FakeCard.mfc1kCustomKey()]);
    late BuildContext ctx;
    await pumpPhoneApp(
      tester,
      comm,
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    );
    final l10n = AppLocalizations.of(ctx)!;
    final (_, mfc, _) = await readHFInfo(ctx, () {});
    final recovery = mfc.recovery!..selectedDictionary = null;
    // nothing found: every sector stays unresolved
    expect(mfc.state, MifareClassicState.checkKeys);
    await recovery.recoverKeys();
    expect(recovery.error, l10n.recovery_error_no_keys_darkside);
    expect(recovery.state, '');
  });
}
