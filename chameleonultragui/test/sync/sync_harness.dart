import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_engine.dart';
import 'package:chameleonultragui/sync/sync_models.dart';

import '../fakes/in_memory_card_store.dart';
import '../fakes/in_memory_dictionary_store.dart';
import '../fakes/in_memory_sync_transport.dart';

const fastOptions = SyncOptions(
  retryInterval: Duration(milliseconds: 25),
  idleTimeout: Duration(seconds: 5),
  handshakeTimeout: Duration(milliseconds: 400),
);

/// One device's stores. Stamps come from [now], advanced by the test.
class Replica {
  int now = 1000;
  late final InMemoryCardStore cards = InMemoryCardStore(clock: () => now);
  late final InMemoryDictionaryStore dicts = InMemoryDictionaryStore(
    clock: () => now,
  );

  // --- exact-stamp seeding (bypasses the local stamping rules) ---
  Future<void> card(String id, int stamp, {String? folder, String name = ''}) =>
      cards.putCardFromSync(
        CardSave(
          id: id,
          uid: '0102',
          name: name.isEmpty ? 'card-$id' : name,
          tag: TagType.mifare1K,
          folderId: folder,
          updatedAt: stamp == 0 ? null : stamp,
          data: [
            Uint8List.fromList([1, 2, 3, 4]),
          ],
        ),
      );

  Future<void> cardFolder(String id, int stamp, {String? parent}) =>
      cards.putFolderFromSync(
        CardFolder(
          id: id,
          name: 'folder-$id',
          parentId: parent,
          updatedAt: stamp == 0 ? null : stamp,
        ),
      );

  Future<void> dict(String id, int stamp, {String? folder, String name = ''}) =>
      dicts.putDictionaryFromSync(
        Dictionary(
          id: id,
          name: name.isEmpty ? 'dict-$id' : name,
          keys: [
            Uint8List.fromList([1, 2, 3, 4, 5, 6]),
          ],
          keyLength: 12,
          folderId: folder,
          updatedAt: stamp == 0 ? null : stamp,
        ),
      );

  Future<void> dictFolder(String id, int stamp, {String? parent}) =>
      dicts.putFolderFromSync(
        DictionaryFolder(
          id: id,
          name: 'dfolder-$id',
          parentId: parent,
          updatedAt: stamp == 0 ? null : stamp,
        ),
      );

  Future<void> dead(SyncEntityKind kind, String id, int deletedAt) {
    final t = SyncTombstone(id: id, kind: kind, deletedAt: deletedAt);
    return kind == SyncEntityKind.card || kind == SyncEntityKind.cardFolder
        ? cards.deleteFromSync(t)
        : dicts.deleteFromSync(t);
  }

  Map<String, String> dump() => {...cards.dump(), ...dicts.dump()};

  Future<Set<String>> tombstoneIds() async => {
    for (final t in await cards.getTombstones()) '${t.kind.name}/${t.id}',
    for (final t in await dicts.getTombstones()) '${t.kind.name}/${t.id}',
  };
}

/// A phone and a watch connected by an in-memory transport.
class SyncPair {
  final Replica phone;
  final Replica watch;
  final InMemorySyncTransport phoneTransport;
  final InMemorySyncTransport watchTransport;
  late SyncEngine phoneEngine;
  late SyncEngine watchEngine;

  SyncPair._(this.phone, this.watch, this.phoneTransport, this.watchTransport);

  factory SyncPair({
    Replica? phone,
    Replica? watch,
    SyncOptions options = fastOptions,
    int chunkSize = 16 * 1024,
    int watchProtocolVersion = kSyncProtocolVersion,
    int watchMinProtocolVersion = kSyncMinProtocolVersion,
  }) {
    final (a, b) = InMemorySyncTransport.pair(chunkSize: chunkSize);
    final p = SyncPair._(phone ?? Replica(), watch ?? Replica(), a, b);
    p.phoneEngine = SyncEngine(
      role: SyncRole.phone,
      transport: a,
      cards: p.phone.cards,
      dictionaries: p.phone.dicts,
      options: options,
      deviceId: 'phone',
      clock: () => p.phone.now,
    );
    p.watchEngine = SyncEngine(
      role: SyncRole.watch,
      transport: b,
      cards: p.watch.cards,
      dictionaries: p.watch.dicts,
      options: options,
      deviceId: 'watch',
      clock: () => p.watch.now,
      protocolVersion: watchProtocolVersion,
      minProtocolVersion: watchMinProtocolVersion,
    );
    p.watchEngine.start();
    return p;
  }

  Future<SyncReport> sync({bool? mirror}) =>
      phoneEngine.sync(mirrorDictionaries: mirror);

  Future<void> dispose() async {
    await phoneEngine.dispose();
    await watchEngine.dispose();
  }
}
