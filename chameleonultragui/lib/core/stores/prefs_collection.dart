// Internal building block of the SharedPreferences-backed stores.
//
// One [PrefsCollection] is one JSON-string-list preference key holding
// entities of a single [SyncEntityKind]. All operations are synchronous (the
// SharedPreferences cache is updated immediately; disk writes are
// fire-and-forget exactly as the legacy `SharedPreferencesProvider` setters).
// That keeps every read-modify-write atomic with respect to the event loop.
import 'dart:async';
import 'dart:convert';

import 'package:chameleonultragui/core/stores/store_change.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default time a tombstone is kept before being pruned on load.
const Duration kDefaultTombstoneRetention = Duration(days: 90);

/// Tombstones of a store (one preference key shared by all of its kinds).
class TombstoneLog {
  final SharedPreferences prefs;
  final String key;

  TombstoneLog(this.prefs, this.key);

  List<SyncTombstone> all() {
    final out = <SyncTombstone>[];
    for (final raw in prefs.getStringList(key) ?? const <String>[]) {
      try {
        out.add(SyncTombstone.fromJson(raw));
      } catch (_) {
        // drop unreadable entries
      }
    }
    return out;
  }

  void _write(List<SyncTombstone> list) {
    prefs.setStringList(key, list.map((t) => t.toJson()).toList());
  }

  /// Records [t]; an existing tombstone for the same kind/id is replaced only
  /// by a newer one.
  void record(SyncTombstone t) {
    final list = all();
    final i = list.indexWhere((x) => x.kind == t.kind && x.id == t.id);
    if (i >= 0) {
      if (list[i].deletedAt >= t.deletedAt) return;
      list[i] = t;
    } else {
      list.add(t);
    }
    _write(list);
  }

  void clear(SyncEntityKind kind, String id) {
    final list = all();
    final before = list.length;
    list.removeWhere((x) => x.kind == kind && x.id == id);
    if (list.length != before) _write(list);
  }

  /// Drops tombstones with `deletedAt < olderThanMs`.
  void prune(int olderThanMs) {
    final list = all();
    final kept = list.where((t) => t.deletedAt >= olderThanMs).toList();
    // Also rewrites when unreadable entries were dropped by [all].
    final raw = prefs.getStringList(key);
    if (kept.length != list.length || (raw?.length ?? 0) != list.length) {
      _write(kept);
    }
  }
}

class PrefsCollection<T> {
  final SharedPreferences prefs;
  final String key;
  final SyncEntityKind kind;
  final TombstoneLog tombstones;
  final String Function(T) idOf;
  final int? Function(T) updatedAtOf;
  final void Function(T, int?) setUpdatedAt;
  final String Function(T) toJson;
  final T Function(String) fromJson;
  final int Function() clock;
  final void Function(StoreChange) emit;

  PrefsCollection({
    required this.prefs,
    required this.key,
    required this.kind,
    required this.tombstones,
    required this.idOf,
    required this.updatedAtOf,
    required this.setUpdatedAt,
    required this.toJson,
    required this.fromJson,
    required this.clock,
    required this.emit,
  });

  /// Raw JSON strings; used to avoid decoding what we only compare.
  List<String> _raw() => prefs.getStringList(key) ?? const <String>[];

  List<T> list() => _raw().map(fromJson).toList();

  T? find(String id) {
    for (final item in list()) {
      if (idOf(item) == id) return item;
    }
    return null;
  }

  void _write(List<T> items) {
    prefs.setStringList(key, items.map(toJson).toList());
  }

  void _emit(String id, StoreChangeType type, StoreChangeOrigin origin) {
    emit(StoreChange(kind: kind, id: id, type: type, origin: origin));
  }

  String _withoutStamp(T item) {
    final map = jsonDecode(toJson(item)) as Map<String, dynamic>;
    map.remove('updatedAt');
    return jsonEncode(map);
  }

  /// Creates or updates [item] with a fresh stamp. Always stamps (an explicit
  /// save is a modification). Returns the stored copy.
  T save(T item) {
    final items = list();
    final id = idOf(item);
    final i = items.indexWhere((x) => idOf(x) == id);
    setUpdatedAt(item, clock());
    if (i >= 0) {
      items[i] = item;
    } else {
      items.add(item);
    }
    _write(items);
    tombstones.clear(kind, id);
    _emit(id, i >= 0 ? StoreChangeType.updated : StoreChangeType.created,
        StoreChangeOrigin.local);
    return fromJson(toJson(item));
  }

  /// Legacy bulk write: makes the stored list equal to [next], stamping only
  /// new or modified items (stamps are set on the caller's objects), keeping
  /// the stamp of unchanged ones and recording a tombstone per removed item.
  /// [skip] filters items that must never be persisted.
  void replaceAll(List<T> next, {bool Function(T)? skip}) {
    final current = {for (final x in list()) idOf(x): x};
    final kept = <T>[];
    final changes = <StoreChange>[];
    final now = clock();
    final nextIds = <String>{};
    for (final item in next) {
      if (skip != null && skip(item)) continue;
      final id = idOf(item);
      nextIds.add(id);
      final old = current[id];
      if (old == null) {
        setUpdatedAt(item, now);
        tombstones.clear(kind, id);
        changes.add(StoreChange(
            kind: kind, id: id, type: StoreChangeType.created));
      } else if (_withoutStamp(old) != _withoutStamp(item)) {
        setUpdatedAt(item, now);
        changes.add(StoreChange(
            kind: kind, id: id, type: StoreChangeType.updated));
      } else {
        setUpdatedAt(item, updatedAtOf(old));
      }
      kept.add(item);
    }
    for (final id in current.keys) {
      if (!nextIds.contains(id)) {
        tombstones.record(SyncTombstone(id: id, kind: kind, deletedAt: now));
        changes.add(StoreChange(
            kind: kind, id: id, type: StoreChangeType.deleted));
      }
    }
    _write(kept);
    changes.forEach(emit);
  }

  /// Deletes [id]; returns whether it existed. No tombstone if absent.
  bool delete(String id) {
    final items = list();
    final before = items.length;
    items.removeWhere((x) => idOf(x) == id);
    if (items.length == before) return false;
    _write(items);
    tombstones.record(SyncTombstone(id: id, kind: kind, deletedAt: clock()));
    _emit(id, StoreChangeType.deleted, StoreChangeOrigin.local);
    return true;
  }

  /// Applies remote state verbatim (keeps the supplied `updatedAt`).
  void putFromSync(T item) {
    final items = list();
    final id = idOf(item);
    final i = items.indexWhere((x) => idOf(x) == id);
    if (i >= 0) {
      items[i] = item;
    } else {
      items.add(item);
    }
    _write(items);
    tombstones.clear(kind, id);
    _emit(id, i >= 0 ? StoreChangeType.updated : StoreChangeType.created,
        StoreChangeOrigin.sync);
  }

  /// Applies a remote deletion: removes the entity (if any, no cascade) and
  /// merges the supplied tombstone verbatim.
  void deleteFromSync(SyncTombstone t) {
    final items = list();
    final before = items.length;
    items.removeWhere((x) => idOf(x) == t.id);
    if (items.length != before) _write(items);
    tombstones.record(t);
    _emit(t.id, StoreChangeType.deleted, StoreChangeOrigin.sync);
  }
}

/// Small helper shared by the two stores.
class StoreChangeBus {
  final StreamController<StoreChange> _controller =
      StreamController<StoreChange>.broadcast();
  Stream<StoreChange> get stream => _controller.stream;
  void add(StoreChange c) {
    if (!_controller.isClosed) _controller.add(c);
  }
}
