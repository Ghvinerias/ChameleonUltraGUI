import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/sync/sync_engine.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/in_memory_card_store.dart';
import '../../fakes/in_memory_dictionary_store.dart';
import '../../fakes/in_memory_sync_transport.dart';

const fastOptions = SyncOptions(
  retryInterval: Duration(milliseconds: 25),
  idleTimeout: Duration(seconds: 5),
  handshakeTimeout: Duration(milliseconds: 300),
);

SyncLinkFactory readyLink(InMemorySyncTransport t) =>
    () async => SyncLinkOpen.ready(t);

SyncLinkFactory unsupportedLink(SyncUnsupportedReason r) =>
    () async => SyncLinkOpen.unsupported(r);

Future<void> seedCard(
  InMemoryCardStore s,
  String id,
  int stamp, {
  int dataBytes = 4,
}) => s.putCardFromSync(
  CardSave(
    id: id,
    uid: '0102',
    name: 'card-$id',
    tag: TagType.mifare1K,
    updatedAt: stamp,
    data: [Uint8List(dataBytes)],
  ),
);

Future<void> seedDict(InMemoryDictionaryStore s, String id, int stamp) =>
    s.putDictionaryFromSync(
      Dictionary(
        id: id,
        name: 'dict-$id',
        keys: [
          Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        ],
        keyLength: 12,
        updatedAt: stamp,
      ),
    );

/// For tests that hold a session open on purpose: the handshake timeout runs
/// on the real clock, which a loaded machine can advance past a short value.
const patientOptions = SyncOptions(
  retryInterval: Duration(milliseconds: 25),
  idleTimeout: Duration(seconds: 60),
  handshakeTimeout: Duration(seconds: 60),
);

/// Pumps until [done] holds, advancing fake time and real time together (the
/// engine uses fake-zone timers; the in-memory link uses microtasks).
Future<void> settle(
  WidgetTester tester,
  bool Function() done, {
  int maxMs = 15000,
}) async {
  for (var i = 0; i < maxMs ~/ 20 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// A raw peer engine on [transport] (no UI), to drive one screen.
SyncEngine rawEngine(
  SyncRole role,
  SyncTransport transport,
  InMemoryCardStore cards,
  InMemoryDictionaryStore dicts, {
  int protocolVersion = kSyncProtocolVersion,
  int minProtocolVersion = kSyncMinProtocolVersion,
  SyncOptions options = fastOptions,
}) => SyncEngine(
  role: role,
  transport: transport,
  cards: cards,
  dictionaries: dicts,
  options: options,
  protocolVersion: protocolVersion,
  minProtocolVersion: minProtocolVersion,
);
