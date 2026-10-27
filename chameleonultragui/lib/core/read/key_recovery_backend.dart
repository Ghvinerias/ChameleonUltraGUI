import 'package:chameleonultragui/recovery/recovery.dart'
    show
        DarksideDart,
        HardNestedDart,
        NestedDart,
        StaticEncryptedNestedDart,
        StaticNestedDart;

/// Thrown by a backend when the attack cannot run at all (for example the
/// native library did not load). Mapped to `ReadErrorCode.recoveryUnavailable`.
class KeyRecoveryUnavailableException implements Exception {
  final Object cause;

  const KeyRecoveryUnavailableException(this.cause);

  @override
  String toString() => 'KeyRecoveryUnavailableException: $cause';
}

/// Mifare Classic key recovery attacks. The read pipeline only talks to this
/// interface so tests can run without the native `librecovery`.
abstract class KeyRecoveryBackend {
  Future<List<int>> darkside(DarksideDart input);

  Future<List<int>> nested(NestedDart input);

  Future<List<int>> staticNested(StaticNestedDart input);

  Future<List<int>> staticEncryptedNested(StaticEncryptedNestedDart input);

  Future<List<int>> hardnested(HardNestedDart input);
}
