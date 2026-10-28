// The seam between the sync screens and the real Wear Data Layer: a factory
// that opens the transport, plus a small splitter that keeps the sync check's
// traffic away from the sync engine (the engine drains bulk transfers it does
// not know).
import 'dart:io' show Platform;

import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:chameleonultragui/sync/wear_data_layer_transport.dart';

enum SyncUnsupportedReason { notAndroid, noPlayServices }

/// Result of opening the link: a usable transport, or the reason sync cannot
/// work on this device.
class SyncLinkOpen {
  const SyncLinkOpen.ready(SyncTransport this.transport) : unsupported = null;
  const SyncLinkOpen.unsupported(SyncUnsupportedReason this.unsupported)
    : transport = null;

  final SyncTransport? transport;
  final SyncUnsupportedReason? unsupported;
}

/// Opens the transport. Tests pass one that returns an
/// `InMemorySyncTransport`.
typedef SyncLinkFactory = Future<SyncLinkOpen> Function();

/// Production factory: the Wear Data Layer on Android with Play Services.
Future<SyncLinkOpen> openWearSyncLink() async {
  if (!Platform.isAndroid) {
    return const SyncLinkOpen.unsupported(SyncUnsupportedReason.notAndroid);
  }
  final t = await WearDataLayerTransport.create();
  if (!t.isSupported) {
    await t.dispose();
    return const SyncLinkOpen.unsupported(SyncUnsupportedReason.noPlayServices);
  }
  return SyncLinkOpen.ready(t);
}

const String kCheckMessagePrefix = 'check.';
const String kCheckBulkKey = 'syncCheck';

/// Splits one transport into an [engineView] and a [checkView]. Messages
/// whose type starts with `check.` and bulks marked `syncCheck` only reach the
/// check view. Disposing the views does nothing; dispose [base] yourself.
class SyncTransportSplit {
  SyncTransportSplit(this.base) {
    engineView = _View(base, forCheck: false);
    checkView = _View(base, forCheck: true);
  }

  final SyncTransport base;
  late final SyncTransport engineView;
  late final SyncTransport checkView;
}

class _View implements SyncTransport {
  _View(this._base, {required this.forCheck});

  final SyncTransport _base;
  final bool forCheck;

  @override
  int get maxMessageBytes => _base.maxMessageBytes;
  @override
  int get preferredChunkSize => _base.preferredChunkSize;
  @override
  Stream<PeerState> get peerState => _base.peerState;
  @override
  PeerState get currentPeerState => _base.currentPeerState;
  @override
  Future<SyncPeer?> getPeer() => _base.getPeer();
  @override
  Future<void> sendMessage(SyncMessage message) => _base.sendMessage(message);
  @override
  Future<BulkSender> openBulk(BulkHeader header) => _base.openBulk(header);

  @override
  Stream<SyncMessage> get messages => _base.messages.where(
    (m) => m.type.startsWith(kCheckMessagePrefix) == forCheck,
  );

  @override
  Stream<IncomingBulk> get incomingBulk => _base.incomingBulk.where(
    (b) => b.header.metadata.containsKey(kCheckBulkKey) == forCheck,
  );

  @override
  Future<void> dispose() async {}
}
