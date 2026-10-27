import 'dart:convert';

import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_engine.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// State notation: `-` absent, `L5` live updatedAt 5, `L0` live without
/// stamp, `D3` tombstone deletedAt 3.
Future<void> _seed(
  Replica r,
  String state,
  String who,
  SyncEntityKind kind,
) async {
  if (state == '-') return;
  final n = int.parse(state.substring(1));
  if (state.startsWith('L')) {
    if (kind == SyncEntityKind.card) {
      await r.card('x', n, name: who);
    } else {
      await r.dict('x', n, name: who);
    }
  } else {
    await r.dead(kind, 'x', n);
  }
}

String? _nameOf(Replica r, SyncEntityKind kind) {
  final d = r.dump();
  final key = kind == SyncEntityKind.card ? 'card/x' : 'dict/x';
  return d[key] == null ? null : (jsonDecode(d[key]!) as Map)['name'] as String;
}

/// expect: '-' (absent everywhere), 'P' (phone content wins), 'W'.
const _rows = <(String, String, String)>[
  ('-', '-', '-'),
  ('L5', '-', 'P'),
  ('-', 'L5', 'W'),
  ('L5', 'L3', 'P'),
  ('L3', 'L5', 'W'),
  ('L5', 'L5', 'P'), // tie -> phone
  ('L0', 'L0', 'P'), // missing stamps tie -> phone
  ('L0', 'L5', 'W'),
  ('L5', 'L0', 'P'),
  ('L5', 'D3', 'P'), // live is newer than the tombstone
  ('L5', 'D5', 'P'), // tie -> phone (live)
  ('L5', 'D7', '-'), // tombstone newer
  ('D3', 'L5', 'W'),
  ('D5', 'L5', '-'), // tie -> phone (delete)
  ('D7', 'L5', '-'),
  ('L0', 'D0', 'P'), // tie at 0 -> phone
  ('D0', 'L0', '-'),
  ('L0', 'D1', '-'),
  ('D1', 'L0', '-'),
  ('D3', 'D5', '-'),
  ('-', 'D5', '-'),
  ('D5', '-', '-'),
];

void main() {
  for (final kind in [SyncEntityKind.card, SyncEntityKind.dictionary]) {
    group('merge table (${kind.name})', () {
      for (final (p, w, expected) in _rows) {
        test('phone $p / watch $w -> $expected', () async {
          final pair = SyncPair();
          await _seed(pair.phone, p, 'P', kind);
          await _seed(pair.watch, w, 'W', kind);
          await pair.sync();
          final want = expected == '-' ? null : expected;
          expect(_nameOf(pair.phone, kind), want);
          expect(_nameOf(pair.watch, kind), want);
          expect(pair.phone.dump(), pair.watch.dump());
          expect((await pair.sync()).isNoOp, isTrue);
          await pair.dispose();
        });
      }
    });
  }

  group('dictionary mirror mode (phone authoritative)', () {
    const mirrorRows = <(String, String, String)>[
      ('L3', 'L5', 'P'), // phone wins even though older
      ('L5', 'L5', 'P'),
      ('L5', '-', 'P'),
      ('-', 'L5', '-'), // watch-only dictionary removed
      ('D9', 'L5', '-'),
      ('L5', 'D9', 'P'), // watch tombstone cannot delete phone data
      ('-', '-', '-'),
      ('D3', '-', '-'),
    ];
    for (final (p, w, expected) in mirrorRows) {
      test('phone $p / watch $w -> $expected', () async {
        final pair = SyncPair();
        await _seed(pair.phone, p, 'P', SyncEntityKind.dictionary);
        await _seed(pair.watch, w, 'W', SyncEntityKind.dictionary);
        await pair.sync(mirror: true);
        final want = expected == '-' ? null : expected;
        expect(_nameOf(pair.phone, SyncEntityKind.dictionary), want);
        expect(_nameOf(pair.watch, SyncEntityKind.dictionary), want);
        expect((await pair.sync(mirror: true)).isNoOp, isTrue);
        await pair.dispose();
      });
    }

    test('does not affect cards and watch edits to dictionaries never reach '
        'the phone', () async {
      final pair = SyncPair();
      await pair.phone.card('c', 3, name: 'P');
      await pair.watch.card('c', 5, name: 'W');
      await pair.phone.dict('d', 3, name: 'P');
      await pair.watch.dict('d', 9, name: 'W');
      await pair.watch.dict('only-watch', 9);
      final r = await pair.sync(mirror: true);
      expect(_nameOf(pair.phone, SyncEntityKind.card), isNull); // id 'x' only
      final cardName = (jsonDecode(pair.phone.dump()['card/c']!) as Map)['name'];
      expect(cardName, 'W'); // normal LWW for cards
      final dictName = (jsonDecode(pair.watch.dump()['dict/d']!) as Map)['name'];
      expect(dictName, 'P');
      expect(pair.watch.dump().containsKey('dict/only-watch'), isFalse);
      expect(r.watch.of(SyncEntityKind.dictionary).deleted, 1);
      expect(r.watch.of(SyncEntityKind.dictionary).updated, 1);
      expect(r.conflictsResolved, 1);
      await pair.dispose();
    });

    test('the mirror flag is taken from the phone, not the watch', () async {
      final pair = SyncPair(options: fastOptions.copyWith(mirrorDictionaries: false));
      await pair.watch.dict('w', 5);
      await pair.sync(mirror: true);
      expect(pair.watch.dump().containsKey('dict/w'), isFalse);
      await pair.dispose();
    });
  });

  group('pure planner', () {
    SyncRecord live(String id, int s, String h) => SyncRecord(
      kind: SyncEntityKind.card,
      id: id,
      live: true,
      stamp: s,
      hash: h,
    );

    test('equal hash means no action even with equal stamps', () {
      final plan = computeSyncPlan(
        phone: {(SyncEntityKind.card, 'a'): live('a', 5, 'h')},
        watch: {(SyncEntityKind.card, 'a'): live('a', 5, 'h')},
      );
      expect(plan.phone.isEmpty && plan.watch.isEmpty, isTrue);
      expect(plan.conflicts, 0);
    });

    test('equal stamp with different content is a conflict won by the phone',
        () {
      final plan = computeSyncPlan(
        phone: {(SyncEntityKind.card, 'a'): live('a', 5, 'p')},
        watch: {(SyncEntityKind.card, 'a'): live('a', 5, 'w')},
      );
      expect(plan.watch.puts.keys, [(SyncEntityKind.card, 'a')]);
      expect(plan.phone.puts, isEmpty);
      expect(plan.conflicts, 1);
    });

    test('resolveRecords: tombstone beats entity only when strictly newer', () {
      final m = SyncManifest(
        entries: [
          const SyncManifestEntry(
            kind: SyncEntityKind.card,
            id: 'a',
            updatedAt: 5,
            hash: 'h',
            size: 1,
          ),
          const SyncManifestEntry(
            kind: SyncEntityKind.card,
            id: 'b',
            updatedAt: 5,
            hash: 'h',
            size: 1,
          ),
        ],
        tombstones: [
          const SyncTombstone(id: 'a', kind: SyncEntityKind.card, deletedAt: 5),
          const SyncTombstone(id: 'b', kind: SyncEntityKind.card, deletedAt: 6),
        ],
      );
      final r = resolveRecords(m);
      expect(r[(SyncEntityKind.card, 'a')]!.live, isTrue);
      expect(r[(SyncEntityKind.card, 'b')]!.live, isFalse);
    });
  });
}
