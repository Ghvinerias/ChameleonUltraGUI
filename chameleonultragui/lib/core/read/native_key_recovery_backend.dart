import 'package:chameleonultragui/core/read/key_recovery_backend.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as native;

/// Default backend: forwards to `lib/recovery/recovery.dart` (FFI).
class NativeKeyRecoveryBackend implements KeyRecoveryBackend {
  const NativeKeyRecoveryBackend();

  Future<List<int>> _run(Future<List<int>> Function() call) async {
    try {
      return await call();
    } on Exception catch (e) {
      throw KeyRecoveryUnavailableException(e);
    } on ArgumentError catch (e) {
      // DynamicLibrary.open reports a missing library as ArgumentError.
      throw KeyRecoveryUnavailableException(e);
    }
  }

  @override
  Future<List<int>> darkside(native.DarksideDart input) =>
      _run(() => native.darkside(input));

  @override
  Future<List<int>> nested(native.NestedDart input) =>
      _run(() => native.nested(input));

  @override
  Future<List<int>> staticNested(native.StaticNestedDart input) =>
      _run(() => native.staticNested(input));

  @override
  Future<List<int>> staticEncryptedNested(
    native.StaticEncryptedNestedDart input,
  ) => _run(() => native.staticEncryptedNested(input));

  @override
  Future<List<int>> hardnested(native.HardNestedDart input) =>
      _run(() => native.hardNested(input));
}
