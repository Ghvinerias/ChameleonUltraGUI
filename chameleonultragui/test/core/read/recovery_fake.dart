import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';

import '../../fakes/fake_card.dart';
import '../../fakes/fake_chameleon_communicator.dart';

/// Adds the attack-related commands the stock fake does not script.
class RecoveryFake extends FakeChameleonCommunicator {
  RecoveryFake(List<FakeCard> cards) : super(cards: cards);

  NTLevel? _nt;

  /// Makes the card report a hard PRNG.
  void ntLevelOverride() => _nt = NTLevel.hard;

  @override
  Future<NTLevel> getMf1NTLevel() async {
    final level = _nt;
    if (level != null) {
      callLog.add('getMf1NTLevel');
      return level;
    }
    return super.getMf1NTLevel();
  }

  @override
  Future<NTDistance> getMf1NTDistance(
    int block,
    int keyType,
    Uint8List keyKnown,
  ) async {
    await beforeCommand?.call('getMf1NTDistance');
    callLog.add('getMf1NTDistance');
    return NTDistance(uid: 0x11223344, distance: 160);
  }

  @override
  Future<NestedNonces> getMf1NestedNonces(
    int block,
    int keyType,
    Uint8List knownKey,
    int targetBlock,
    int targetKeyType, {
    NTLevel level = NTLevel.weak,
    bool slow = false,
  }) async {
    callLog.add('getMf1NestedNonces(${level.name})');
    if (level == NTLevel.hard) return NestedNonces(nonces: []);
    return NestedNonces(
      nonces: [
        NestedNonce(nt: 1, ntEnc: 2, parity: 0),
        NestedNonce(nt: 3, ntEnc: 4, parity: 0),
      ],
    );
  }
}
