import 'dart:convert';
import 'dart:math';

import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

const _cardIds = ['c0', 'c1', 'c2', 'c3', 'c4', 'c5'];
const _folderIds = ['f0', 'f1', 'f2', 'f3'];
const _dictIds = ['d0', 'd1', 'd2'];
const _dictFolderIds = ['g0', 'g1'];

/// Global clock shared by both replicas. With [ties] it advances by 0 or 1 so
/// equal stamps happen; otherwise every operation gets a unique stamp.
class _Clock {
  int t = 1000;
  final bool ties;
  final Random rnd;
  _Clock(this.ties, this.rnd);
  int tick() {
    t += ties ? rnd.nextInt(2) : 1;
    return t;
  }
}

String? _pick(Random rnd, List<String> ids) =>
    rnd.nextInt(3) == 0 ? null : ids[rnd.nextInt(ids.length)];

/// Would pointing [id] at [parent] make a cycle in the folder tree?
bool _cycle(Map<String, String?> parents, String id, String? parent) {
  var cur = parent;
  var n = 0;
  while (cur != null && n++ < 20) {
    if (cur == id) return true;
    cur = parents[cur];
  }
  return false;
}

Future<void> _randomOps(Replica r, Random rnd, _Clock clock, int n) async {
  for (var i = 0; i < n; i++) {
    r.now = clock.tick();
    switch (rnd.nextInt(10)) {
      case 0 || 1 || 2:
        final id = _cardIds[rnd.nextInt(_cardIds.length)];
        // Only reference folders that exist locally (like the real UI).
        final folders = (await r.cards.getFolders()).map((f) => f.id).toList();
        final folder = folders.isEmpty || rnd.nextInt(3) == 0
            ? null
            : folders[rnd.nextInt(folders.length)];
        await r.cards.saveCard(
          CardSave(
            id: id,
            uid: '01',
            name: 'n${rnd.nextInt(1000)}',
            tag: TagType.mifare1K,
            folderId: folder,
          ),
        );
      case 3:
        await r.cards.deleteCard(_cardIds[rnd.nextInt(_cardIds.length)]);
      case 4 || 5:
        final id = _folderIds[rnd.nextInt(_folderIds.length)];
        final parents = {
          for (final f in await r.cards.getFolders()) f.id: f.parentId,
        };
        var parent = _pick(rnd, _folderIds);
        if (parent != null &&
            (!parents.containsKey(parent) || _cycle(parents, id, parent))) {
          parent = null;
        }
        await r.cards.saveFolder(
          CardFolder(id: id, name: 'f${rnd.nextInt(1000)}', parentId: parent),
        );
      case 6:
        await r.cards.deleteFolder(
          _folderIds[rnd.nextInt(_folderIds.length)],
          deleteContents: rnd.nextBool(),
        );
      case 7:
        final folders = (await r.dicts.getFolders()).map((f) => f.id).toList();
        await r.dicts.saveDictionary(
          Dictionary(
            id: _dictIds[rnd.nextInt(_dictIds.length)],
            name: 'd${rnd.nextInt(1000)}',
            keyLength: 12,
            folderId: folders.isEmpty || rnd.nextBool()
                ? null
                : folders[rnd.nextInt(folders.length)],
          ),
        );
      case 8:
        await r.dicts.deleteDictionary(_dictIds[rnd.nextInt(_dictIds.length)]);
      default:
        if (rnd.nextBool()) {
          await r.dicts.saveFolder(
            DictionaryFolder(
              id: _dictFolderIds[rnd.nextInt(_dictFolderIds.length)],
              name: 'g${rnd.nextInt(1000)}',
            ),
          );
        } else {
          await r.dicts.deleteFolder(
            _dictFolderIds[rnd.nextInt(_dictFolderIds.length)],
            deleteContents: rnd.nextBool(),
          );
        }
    }
  }
}

/// No dangling folder references, no folder cycles.
Future<void> _expectWellFormed(Replica r) async {
  final cardFolders = {for (final f in await r.cards.getFolders()) f.id: f};
  for (final c in await r.cards.getCards()) {
    if (c.folderId != null) {
      expect(
        cardFolders.containsKey(c.folderId),
        isTrue,
        reason: 'card ${c.id}',
      );
    }
  }
  final parents = {for (final f in cardFolders.values) f.id: f.parentId};
  for (final f in cardFolders.values) {
    if (f.parentId != null) {
      expect(
        cardFolders.containsKey(f.parentId),
        isTrue,
        reason: 'folder ${f.id}',
      );
    }
    expect(
      _cycle(parents, f.id, f.parentId),
      isFalse,
      reason: 'cycle at ${f.id}',
    );
  }
  final dictFolders = {for (final f in await r.dicts.getFolders()) f.id};
  for (final d in await r.dicts.getDictionaries()) {
    if (d.folderId != null) {
      expect(dictFolders.contains(d.folderId), isTrue, reason: 'dict ${d.id}');
    }
  }
}

Future<void> _scenario(
  int seed, {
  required bool ties,
  required bool mirror,
}) async {
  final rnd = Random(seed);
  final clock = _Clock(ties, rnd);
  final pair = SyncPair();
  for (var round = 0; round < 3; round++) {
    await _randomOps(pair.phone, rnd, clock, rnd.nextInt(9));
    await _randomOps(pair.watch, rnd, clock, rnd.nextInt(9));
    await pair.sync(mirror: mirror);
    final label = 'seed $seed round $round';
    expect(pair.phone.dump(), pair.watch.dump(), reason: label);
    await _expectWellFormed(pair.phone);
    await _expectWellFormed(pair.watch);
    final snapshot = pair.phone.dump();
    final again = await pair.sync(mirror: mirror);
    expect(again.isNoOp, isTrue, reason: '$label: second sync must be a no-op');
    expect(pair.phone.dump(), snapshot, reason: label);
    expect(pair.watch.dump(), snapshot, reason: label);
  }
  await pair.dispose();
}

/// Runs the same operations with replica A as phone, then as watch.
Future<(Map<String, String>, Map<String, String>)> _direction(
  int seed,
  bool aIsPhone,
) async {
  final rnd = Random(seed);
  final clock = _Clock(false, rnd);
  final a = Replica();
  final b = Replica();
  final pair = aIsPhone
      ? SyncPair(phone: a, watch: b)
      : SyncPair(phone: b, watch: a);
  for (var round = 0; round < 2; round++) {
    await _randomOps(a, rnd, clock, rnd.nextInt(9));
    await _randomOps(b, rnd, clock, rnd.nextInt(9));
    await pair.sync();
  }
  final result = (a.dump(), b.dump());
  await pair.dispose();
  return result;
}

void main() {
  test('randomized convergence, unique stamps (60 seeds)', () async {
    for (var seed = 0; seed < 60; seed++) {
      await _scenario(seed, ties: false, mirror: false);
    }
  });

  test('randomized convergence with equal-stamp ties (60 seeds)', () async {
    for (var seed = 1000; seed < 1060; seed++) {
      await _scenario(seed, ties: true, mirror: false);
    }
  });

  test('randomized convergence in dictionary mirror mode (40 seeds)', () async {
    for (var seed = 2000; seed < 2040; seed++) {
      await _scenario(seed, ties: false, mirror: true);
    }
  });

  test(
    'sync direction is commutative when stamps are unique (40 seeds)',
    () async {
      for (var seed = 3000; seed < 3040; seed++) {
        final x = await _direction(seed, true);
        final y = await _direction(seed, false);
        expect(x.$1, y.$1, reason: 'seed $seed replica A');
        expect(x.$2, y.$2, reason: 'seed $seed replica B');
        expect(x.$1, x.$2);
      }
    },
  );

  test(
    'with ties the phone side wins, whichever replica plays the phone',
    () async {
      for (final aIsPhone in [true, false]) {
        final a = Replica();
        final b = Replica();
        await a.card('x', 5, name: 'A');
        await b.card('x', 5, name: 'B');
        final pair = aIsPhone
            ? SyncPair(phone: a, watch: b)
            : SyncPair(phone: b, watch: a);
        await pair.sync();
        final winner = aIsPhone ? 'A' : 'B';
        for (final r in [a, b]) {
          expect((jsonDecode(r.dump()['card/x']!) as Map)['name'], winner);
        }
        await pair.dispose();
      }
    },
  );
}
