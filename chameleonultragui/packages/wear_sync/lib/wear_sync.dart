import 'dart:async';

import 'package:flutter/services.dart';

/// Result of `getStatus`.
class WearSyncStatus {
  /// False when Google Play Services / the Wearable API is missing.
  final bool available;
  final String? reason;
  final int maxMessageBytes;

  const WearSyncStatus({
    required this.available,
    this.reason,
    this.maxMessageBytes = 100 * 1024,
  });

  static const unavailable = WearSyncStatus(
    available: false,
    reason: 'unsupported_platform',
  );
}

class WearPeerInfo {
  final String id;
  final String name;
  final bool nearby;

  const WearPeerInfo({required this.id, this.name = '', this.nearby = false});
}

/// Native -> Dart events.
sealed class WearSyncEvent {
  const WearSyncEvent();
}

class WearPeerEvent extends WearSyncEvent {
  final WearPeerInfo? peer; // null = no peer reachable
  const WearPeerEvent(this.peer);
}

class WearMessageEvent extends WearSyncEvent {
  final Uint8List bytes;
  const WearMessageEvent(this.bytes);
}

class WearIncomingBulkEvent extends WearSyncEvent {
  final String transferId;

  /// Opaque header bytes exactly as the sender passed to `openBulk`.
  final Uint8List header;
  const WearIncomingBulkEvent(this.transferId, this.header);
}

class WearChunkEvent extends WearSyncEvent {
  final String transferId;
  final int index;
  final Uint8List bytes;
  const WearChunkEvent(this.transferId, this.index, this.bytes);
}

class WearBulkEndEvent extends WearSyncEvent {
  final String transferId;
  const WearBulkEndEvent(this.transferId);
}

/// [reason]: `cancelledByPeer`, `linkLost` or `error`.
class WearBulkAbortedEvent extends WearSyncEvent {
  final String transferId;
  final String reason;
  const WearBulkAbortedEvent(this.transferId, this.reason);
}

/// Error from the native side. [code]: `unavailable`, `no_peer`, `too_large`,
/// `no_transfer`, `link_lost`, `bad_args`, `failed`.
class WearSyncException implements Exception {
  final String code;
  final String? message;
  const WearSyncException(this.code, [this.message]);

  @override
  String toString() => 'WearSyncException($code: $message)';
}

/// Platform layer; swap for a fake in tests.
abstract class WearSyncPlatform {
  Future<WearSyncStatus> getStatus();
  Future<WearPeerInfo?> getPeer();
  Future<void> sendMessage(Uint8List bytes);
  Future<void> openBulk(String transferId, Uint8List header);
  Future<void> sendChunk(String transferId, int index, Uint8List bytes);
  Future<void> endBulk(String transferId);

  /// Cancels an outgoing or incoming transfer. No-op for unknown ids.
  Future<void> cancelBulk(String transferId);

  /// Single-subscription stream. The first listen starts native listeners and
  /// emits the current [WearPeerEvent]; cancelling removes them and aborts
  /// open transfers.
  Stream<WearSyncEvent> get events;
}

/// MethodChannel/EventChannel implementation. Android only; on other
/// platforms reports [WearSyncStatus.unavailable].
class MethodChannelWearSync implements WearSyncPlatform {
  static const MethodChannel _method = MethodChannel(
    'io.chameleon.ultra/wear_sync',
  );
  static const EventChannel _events = EventChannel(
    'io.chameleon.ultra/wear_sync/events',
  );

  Future<T?> _call<T>(String name, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(name, args);
    } on PlatformException catch (e) {
      throw WearSyncException(e.code, e.message);
    }
  }

  @override
  Future<WearSyncStatus> getStatus() async {
    try {
      final m = await _call<Map<Object?, Object?>>('getStatus');
      if (m == null) return WearSyncStatus.unavailable;
      return WearSyncStatus(
        available: m['available'] == true,
        reason: m['reason'] as String?,
        maxMessageBytes: (m['maxMessageBytes'] as int?) ?? 100 * 1024,
      );
    } on MissingPluginException {
      return WearSyncStatus.unavailable;
    }
  }

  @override
  Future<WearPeerInfo?> getPeer() async =>
      _peer(await _call<Map<Object?, Object?>>('getPeer'));

  static WearPeerInfo? _peer(Map<Object?, Object?>? m) => m == null
      ? null
      : WearPeerInfo(
          id: m['id'] as String,
          name: (m['name'] as String?) ?? '',
          nearby: m['nearby'] == true,
        );

  @override
  Future<void> sendMessage(Uint8List bytes) =>
      _call<void>('sendMessage', {'bytes': bytes});

  @override
  Future<void> openBulk(String transferId, Uint8List header) =>
      _call<void>('openBulk', {'transferId': transferId, 'header': header});

  @override
  Future<void> sendChunk(String transferId, int index, Uint8List bytes) =>
      _call<void>('sendChunk', {
        'transferId': transferId,
        'index': index,
        'bytes': bytes,
      });

  @override
  Future<void> endBulk(String transferId) =>
      _call<void>('endBulk', {'transferId': transferId});

  @override
  Future<void> cancelBulk(String transferId) =>
      _call<void>('cancelBulk', {'transferId': transferId});

  @override
  Stream<WearSyncEvent> get events => _events
      .receiveBroadcastStream()
      .map((e) => _parse(Map<Object?, Object?>.from(e as Map)))
      .where((e) => e != null)
      .cast<WearSyncEvent>();

  static WearSyncEvent? _parse(Map<Object?, Object?> m) {
    switch (m['event']) {
      case 'peer':
        return WearPeerEvent(
          m['available'] == true && m['id'] != null
              ? WearPeerInfo(
                  id: m['id'] as String,
                  name: (m['name'] as String?) ?? '',
                  nearby: m['nearby'] == true,
                )
              : null,
        );
      case 'message':
        return WearMessageEvent(m['bytes'] as Uint8List);
      case 'incomingBulk':
        return WearIncomingBulkEvent(
          m['transferId'] as String,
          m['header'] as Uint8List,
        );
      case 'chunk':
        return WearChunkEvent(
          m['transferId'] as String,
          m['index'] as int,
          m['bytes'] as Uint8List,
        );
      case 'bulkEnd':
        return WearBulkEndEvent(m['transferId'] as String);
      case 'bulkAborted':
        return WearBulkAbortedEvent(
          m['transferId'] as String,
          m['reason'] as String,
        );
    }
    return null;
  }
}
