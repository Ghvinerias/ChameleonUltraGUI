// Records, snapshots and the pure merge planner of the sync engine (T4).
//
// A *record* is the resolved state of one entity on one replica: live (with
// its `updatedAt`, 0 when missing) or dead (tombstone with `deletedAt`).
// [computeSyncPlan] is a pure function of two replicas' records; both sides
// run it on the same inputs and therefore agree on the outcome.
import 'dart:convert';

import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/models/sync_extensions.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:crypto/crypto.dart';

typedef SyncKey = (SyncEntityKind, String);

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

class SyncRecord {
  final SyncEntityKind kind;
  final String id;
  final bool live;

  /// `updatedAt` (live) or `deletedAt` (dead).
  final int stamp;

  /// SHA-256 of the entity JSON; empty for dead records.
  final String hash;
  final int size;

  const SyncRecord({
    required this.kind,
    required this.id,
    required this.live,
    required this.stamp,
    this.hash = '',
    this.size = 0,
  });

  SyncKey get key => (kind, id);

  @override
  bool operator ==(Object other) =>
      other is SyncRecord &&
      other.kind == kind &&
      other.id == id &&
      other.live == live &&
      other.stamp == stamp &&
      other.hash == hash &&
      other.size == size;

  @override
  int get hashCode => Object.hash(kind, id, live, stamp, hash, size);

  @override
  String toString() =>
      'SyncRecord($kind $id ${live ? 'live' : 'dead'}@$stamp)';
}

/// Resolves a manifest into one record per entity. When an entity and a
/// tombstone share an id, the tombstone wins iff `deletedAt > updatedAt`.
Map<SyncKey, SyncRecord> resolveRecords(SyncManifest manifest) {
  final result = <SyncKey, SyncRecord>{};
  for (final e in manifest.entries) {
    if (e.kind.isDictionaryFamily &&
        !e.kind.isFolder &&
        e.id.isEmpty) {
      continue;
    }
    final existing = result[(e.kind, e.id)];
    if (existing == null || e.updatedAt > existing.stamp) {
      result[(e.kind, e.id)] = SyncRecord(
        kind: e.kind,
        id: e.id,
        live: true,
        stamp: e.updatedAt,
        hash: e.hash,
        size: e.size,
      );
    }
  }
  for (final t in manifest.tombstones) {
    final key = (t.kind, t.id);
    final existing = result[key];
    if (existing == null) {
      result[key] = SyncRecord(
        kind: t.kind,
        id: t.id,
        live: false,
        stamp: t.deletedAt,
      );
    } else if (existing.live) {
      if (t.deletedAt > existing.stamp) {
        result[key] = SyncRecord(
          kind: t.kind,
          id: t.id,
          live: false,
          stamp: t.deletedAt,
        );
      }
    } else if (t.deletedAt > existing.stamp) {
      result[key] = SyncRecord(
        kind: t.kind,
        id: t.id,
        live: false,
        stamp: t.deletedAt,
      );
    }
  }
  return result;
}

/// Everything the engine knows about one replica at one instant.
class SyncSnapshot {
  /// Canonical JSON of every live entity.
  final Map<SyncKey, String> json;
  final Map<SyncKey, SyncTombstone> tombstones;
  final SyncManifest manifest;
  final Map<SyncKey, SyncRecord> records;

  SyncSnapshot._(this.json, this.tombstones, this.manifest, this.records);

  static Future<SyncSnapshot> capture(
    CardStore cards,
    DictionaryStore dictionaries,
  ) async {
    final json = <SyncKey, String>{};
    final updated = <SyncKey, int>{};
    for (final c in await cards.getCards()) {
      json[(c.syncKind, c.id)] = c.toJson();
      updated[(c.syncKind, c.id)] = c.syncStamp;
    }
    for (final f in await cards.getFolders()) {
      json[(f.syncKind, f.id)] = f.toJson();
      updated[(f.syncKind, f.id)] = f.syncStamp;
    }
    for (final d in await dictionaries.getDictionaries()) {
      if (!d.isSyncable) continue;
      json[(d.syncKind, d.id)] = d.toJson();
      updated[(d.syncKind, d.id)] = d.syncStamp;
    }
    for (final f in await dictionaries.getFolders()) {
      json[(f.syncKind, f.id)] = f.toJson();
      updated[(f.syncKind, f.id)] = f.syncStamp;
    }

    final tombstones = <SyncKey, SyncTombstone>{};
    void addTombstones(List<SyncTombstone> list, bool Function(SyncEntityKind) ok) {
      for (final t in list) {
        if (!ok(t.kind)) continue;
        if (t.kind == SyncEntityKind.dictionary && t.id.isEmpty) continue;
        final k = (t.kind, t.id);
        final old = tombstones[k];
        if (old == null || t.deletedAt > old.deletedAt) tombstones[k] = t;
      }
    }

    addTombstones(await cards.getTombstones(), (k) => k.isCardFamily);
    addTombstones(
      await dictionaries.getTombstones(),
      (k) => k.isDictionaryFamily,
    );

    final keys = json.keys.toList()..sort(_compareKeys);
    final entries = [
      for (final k in keys)
        SyncManifestEntry(
          kind: k.$1,
          id: k.$2,
          updatedAt: updated[k]!,
          hash: sha256Hex(utf8.encode(json[k]!)),
          size: utf8.encode(json[k]!).length,
        ),
    ];
    final tombKeys = tombstones.keys.toList()..sort(_compareKeys);
    final manifest = SyncManifest(
      entries: entries,
      tombstones: [for (final k in tombKeys) tombstones[k]!],
    );
    return SyncSnapshot._(json, tombstones, manifest, resolveRecords(manifest));
  }
}

int _compareKeys(SyncKey a, SyncKey b) {
  final c = a.$1.index.compareTo(b.$1.index);
  return c != 0 ? c : a.$2.compareTo(b.$2);
}

/// An entity the local side must take from the peer.
class SyncPut {
  /// The peer's record (always the winner).
  final SyncRecord source;

  /// Whether the local side currently holds a live version (update vs add).
  final bool replacesLive;

  const SyncPut(this.source, this.replacesLive);
}

/// What one side has to do locally.
class SyncSideActions {
  final Map<SyncKey, SyncPut> puts = {};
  final Map<SyncKey, SyncTombstone> deletes = {};

  bool get isEmpty => puts.isEmpty && deletes.isEmpty;
}

class SyncPlan {
  final SyncSideActions phone = SyncSideActions();
  final SyncSideActions watch = SyncSideActions();

  /// Keys that are live on both replicas once the plan is applied.
  final Set<SyncKey> finalLive = {};

  /// Equal-stamp ties and mirror overrides decided by the phone-wins rules.
  int conflicts = 0;

  SyncSideActions forRole(SyncRole role) =>
      role == SyncRole.phone ? phone : watch;
}

/// Pure three-way-free merge (last writer wins per id, tombstones, ties to
/// the phone). See `docs/wear-contracts.md` ("Sync merge rules").
///
/// With [mirrorDictionaries] the phone is authoritative for dictionaries and
/// dictionary folders: the watch gets exactly the phone's state, watch-only
/// entries are deleted, and nothing ever flows watch -> phone for them.
SyncPlan computeSyncPlan({
  required Map<SyncKey, SyncRecord> phone,
  required Map<SyncKey, SyncRecord> watch,
  bool mirrorDictionaries = false,
}) {
  final plan = SyncPlan();
  final keys = {...phone.keys, ...watch.keys}.toList()..sort(_compareKeys);
  for (final key in keys) {
    final p = phone[key];
    final w = watch[key];
    final kind = key.$1;
    final id = key.$2;

    void putTo(SyncSideActions to, SyncRecord src, SyncRecord? local) {
      to.puts[key] = SyncPut(src, local?.live ?? false);
    }

    void deleteOn(SyncSideActions on, int deletedAt) {
      on.deletes[key] = SyncTombstone(id: id, kind: kind, deletedAt: deletedAt);
    }

    if (mirrorDictionaries && kind.isDictionaryFamily) {
      if (p != null && p.live) {
        plan.finalLive.add(key);
        if (w == null || !w.live) {
          putTo(plan.watch, p, w);
        } else if (w.hash != p.hash) {
          putTo(plan.watch, p, w);
          plan.conflicts++;
        }
      } else if (w != null && w.live) {
        deleteOn(plan.watch, p != null ? p.stamp : w.stamp);
      }
      continue;
    }

    if (p == null || w == null) {
      final only = (p ?? w)!;
      if (only.live) {
        plan.finalLive.add(key);
        if (p == null) {
          putTo(plan.phone, only, null);
        } else {
          putTo(plan.watch, only, null);
        }
      }
      continue;
    }

    if (p.live && w.live) {
      plan.finalLive.add(key);
      if (p.hash == w.hash) continue;
      if (p.stamp == w.stamp) plan.conflicts++;
      if (p.stamp >= w.stamp) {
        putTo(plan.watch, p, w);
      } else {
        putTo(plan.phone, w, p);
      }
    } else if (p.live && !w.live) {
      // Watch holds a tombstone. It wins iff deletedAt > updatedAt; a tie
      // goes to the phone, which holds the live entity.
      if (w.stamp > p.stamp) {
        deleteOn(plan.phone, w.stamp);
      } else {
        plan.finalLive.add(key);
        putTo(plan.watch, p, w);
      }
    } else if (!p.live && w.live) {
      // Phone holds the tombstone; a tie goes to the phone (delete).
      if (p.stamp >= w.stamp) {
        deleteOn(plan.watch, p.stamp);
      } else {
        plan.finalLive.add(key);
        putTo(plan.phone, w, p);
      }
    }
    // Both dead: nothing to do (tombstones are only propagated to replicas
    // that still hold a live copy).
  }
  return plan;
}
