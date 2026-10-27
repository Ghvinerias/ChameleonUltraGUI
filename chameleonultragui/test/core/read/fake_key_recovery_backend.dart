import 'package:chameleonultragui/core/read/key_recovery_backend.dart';
import 'package:chameleonultragui/recovery/recovery.dart';

/// Scripted [KeyRecoveryBackend]: each attack returns [results] (default: no
/// keys) and records its calls in [calls]. Set [unavailable] to make every
/// attack throw [KeyRecoveryUnavailableException].
class FakeKeyRecoveryBackend implements KeyRecoveryBackend {
  final List<String> calls = [];
  final Map<String, List<int>> results;
  bool unavailable;

  FakeKeyRecoveryBackend({this.results = const {}, this.unavailable = false});

  Future<List<int>> _answer(String name) async {
    calls.add(name);
    if (unavailable) {
      throw const KeyRecoveryUnavailableException('librecovery missing');
    }
    return results[name] ?? const [];
  }

  @override
  Future<List<int>> darkside(DarksideDart input) => _answer('darkside');

  @override
  Future<List<int>> nested(NestedDart input) => _answer('nested');

  @override
  Future<List<int>> staticNested(StaticNestedDart input) =>
      _answer('staticNested');

  @override
  Future<List<int>> staticEncryptedNested(StaticEncryptedNestedDart input) =>
      _answer('staticEncryptedNested');

  @override
  Future<List<int>> hardnested(HardNestedDart input) => _answer('hardnested');
}
