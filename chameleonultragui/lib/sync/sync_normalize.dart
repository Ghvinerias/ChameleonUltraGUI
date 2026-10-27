// Orphan repair (T4). After a merge every live item must sit in a live folder
// and the folder graph must be a forest. Rule (documented in
// docs/wear-contracts.md): an item or folder whose parent is not live after
// the merge moves to the root (field removed, `updatedAt` untouched); a
// parent cycle (two replicas moved folders into each other) is broken by
// moving the cycle member with the smallest id to the root.
//
// The function is deterministic over the final merged content, so both
// replicas compute the same result without exchanging it.
import 'dart:convert';

import 'package:chameleonultragui/models/sync_extensions.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_records.dart';

/// Returns the rewritten JSON for every entity of [finalJson] that must change.
Map<SyncKey, String> normalizeOrphans(Map<SyncKey, String> finalJson) {
  final rewritten = <SyncKey, String>{};
  for (final folderKind in [
    SyncEntityKind.cardFolder,
    SyncEntityKind.dictionaryFolder,
  ]) {
    final parents = <String, String?>{};
    final folderMaps = <String, Map<String, dynamic>>{};
    for (final e in finalJson.entries) {
      if (e.key.$1 != folderKind) continue;
      final m = jsonDecode(e.value) as Map<String, dynamic>;
      folderMaps[e.key.$2] = m;
      parents[e.key.$2] = m['parentId'] as String?;
    }
    final changedFolders = <String>{};
    for (final id in parents.keys.toList()..sort()) {
      final p = parents[id];
      if (p != null && !parents.containsKey(p)) {
        parents[id] = null;
        changedFolders.add(id);
      }
    }
    for (final id in parents.keys.toList()..sort()) {
      if (_onCycle(parents, id)) {
        parents[id] = null;
        changedFolders.add(id);
      }
    }
    for (final id in changedFolders) {
      final m = folderMaps[id]!..remove('parentId');
      rewritten[(folderKind, id)] = jsonEncode(m);
    }

    for (final e in finalJson.entries) {
      final kind = e.key.$1;
      if (kind.isFolder || kind.folderKind != folderKind) continue;
      final m = jsonDecode(e.value) as Map<String, dynamic>;
      final f = m['folderId'] as String?;
      if (f != null && !parents.containsKey(f)) {
        m.remove('folderId');
        rewritten[e.key] = jsonEncode(m);
      }
    }
  }
  return rewritten;
}

bool _onCycle(Map<String, String?> parents, String id) {
  var cur = parents[id];
  var steps = 0;
  while (cur != null && steps <= parents.length) {
    if (cur == id) return true;
    cur = parents[cur];
    steps++;
  }
  return false;
}

/// Depth of [id] in a folder forest given by [parentOf] (cycle-safe).
int folderDepth(String id, String? Function(String) parentOf, int limit) {
  var depth = 0;
  var cur = parentOf(id);
  while (cur != null && depth <= limit) {
    depth++;
    cur = parentOf(cur);
  }
  return depth;
}
