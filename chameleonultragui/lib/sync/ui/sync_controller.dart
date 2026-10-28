// State holder shared by the phone "Watch sync" page and the watch Sync screen:
// owns the transport, the sync engine and the sync check for the lifetime of
// one screen.
import 'dart:async';

import 'package:chameleonultragui/core/stores/card_store.dart';
import 'package:chameleonultragui/core/stores/dictionary_store.dart';
import 'package:chameleonultragui/models/sync_tombstone.dart';
import 'package:chameleonultragui/sync/sync_engine.dart';
import 'package:chameleonultragui/sync/sync_models.dart';
import 'package:chameleonultragui/sync/sync_transport.dart';
import 'package:chameleonultragui/sync/ui/sync_check.dart';
import 'package:chameleonultragui/sync/ui/sync_link.dart';
import 'package:flutter/foundation.dart';

enum SyncAvailability {
  /// The link is being opened.
  starting,

  /// Sync cannot work on this device (see [SyncUiController.unsupported]).
  unsupported,

  /// Supported, but the other device is not reachable.
  peerUnavailable,

  /// The other device is reachable.
  peerAvailable,
}

class SyncUiController extends ChangeNotifier {
  SyncUiController({
    required this.role,
    required this.linkFactory,
    required this.cards,
    required this.dictionaries,
    this.options = const SyncOptions(),
    bool mirrorDictionaries = false,
    this.onMirrorChanged,
    this.checkPayloadBytes = 1024 * 1024,
    this.checkTransferTimeout = const Duration(seconds: 30),
  }) : _mirror = mirrorDictionaries;

  final SyncRole role;
  final SyncLinkFactory linkFactory;
  final CardStore cards;
  final DictionaryStore dictionaries;
  final SyncOptions options;
  final void Function(bool)? onMirrorChanged;
  final int checkPayloadBytes;
  final Duration checkTransferTimeout;

  bool get canInitiate => role == SyncRole.phone;

  SyncAvailability _availability = SyncAvailability.starting;
  SyncUnsupportedReason? _unsupported;
  bool _mirror;
  bool _disposed = false;

  SyncTransport? _base;
  SyncEngine? _engine;
  SyncCheck? _check;
  StreamSubscription<PeerState>? _peerSub;
  StreamSubscription<SyncEvent>? _eventSub;
  StreamSubscription<dynamic>? _cardSub;
  StreamSubscription<dynamic>? _dictSub;

  // current / last run
  bool _running = false;
  SyncPhase? _phase;
  int _bytes = 0;
  int _bytesTotal = 0;
  SyncReport? _lastReport;
  SyncException? _lastError;
  Map<SyncEntityKind, int> _library = {};
  bool _countsBusy = false;
  bool _countsDirty = false;

  // check
  bool _checkRunning = false;
  SyncCheckStage? _checkStage;
  SyncCheckResult? _checkResult;

  SyncAvailability get availability => _availability;
  SyncUnsupportedReason? get unsupported => _unsupported;
  bool get mirrorDictionaries => _mirror;
  bool get running => _running;
  SyncPhase? get phase => _phase;
  int get bytesTransferred => _bytes;
  int get bytesTotal => _bytesTotal;

  /// 0..1 while transferring, null while there is nothing to measure yet.
  double? get progress {
    if (!_running) return null;
    if (_phase == SyncPhase.committing || _phase == SyncPhase.verifying) {
      return 1;
    }
    if (_phase != SyncPhase.transferring || _bytesTotal == 0) return null;
    return (_bytes / _bytesTotal).clamp(0.0, 1.0);
  }

  SyncReport? get lastReport => _lastReport;
  SyncException? get lastError => _lastError;
  Map<SyncEntityKind, int> get libraryCounts => _library;

  bool get checkRunning => _checkRunning;
  SyncCheckStage? get checkStage => _checkStage;
  SyncCheckResult? get checkResult => _checkResult;

  bool get canSyncNow =>
      canInitiate &&
      !_running &&
      !_checkRunning &&
      _availability == SyncAvailability.peerAvailable;

  bool get canRunCheck =>
      !_running &&
      !_checkRunning &&
      _availability == SyncAvailability.peerAvailable;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Opens the link, starts the engine and the check responder. Safe to call
  /// once; never throws.
  Future<void> start() async {
    SyncLinkOpen open;
    try {
      open = await linkFactory();
    } catch (_) {
      open = const SyncLinkOpen.unsupported(
        SyncUnsupportedReason.noPlayServices,
      );
    }
    final t = open.transport;
    if (_disposed) {
      await t?.dispose();
      return;
    }
    if (t == null) {
      _unsupported = open.unsupported;
      _availability = SyncAvailability.unsupported;
      _changed();
      return;
    }
    _base = t;
    final split = SyncTransportSplit(t);
    final engine = _engine = SyncEngine(
      role: role,
      transport: split.engineView,
      cards: cards,
      dictionaries: dictionaries,
      options: options.copyWith(mirrorDictionaries: _mirror),
    );
    _eventSub = engine.events.listen(_onEvent);
    engine.start();
    (_check = SyncCheck(
      transport: split.checkView,
      payloadBytes: checkPayloadBytes,
      transferTimeout: checkTransferTimeout,
    )).startResponder();
    _peerSub = t.peerState.listen((s) {
      _availability = s == PeerState.available
          ? SyncAvailability.peerAvailable
          : SyncAvailability.peerUnavailable;
      _changed();
    });
    _availability = t.currentPeerState == PeerState.available
        ? SyncAvailability.peerAvailable
        : SyncAvailability.peerUnavailable;
    _cardSub = cards.changes.listen((_) => _refreshCounts());
    _dictSub = dictionaries.changes.listen((_) => _refreshCounts());
    _changed();
    await _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    if (_countsBusy) {
      _countsDirty = true;
      return;
    }
    _countsBusy = true;
    try {
      do {
        _countsDirty = false;
        final counts = {
          SyncEntityKind.card: (await cards.getCards()).length,
          SyncEntityKind.cardFolder: (await cards.getFolders()).length,
          SyncEntityKind.dictionary:
              (await dictionaries.getDictionaries()).length,
          SyncEntityKind.dictionaryFolder:
              (await dictionaries.getFolders()).length,
        };
        if (_disposed) return;
        _library = counts;
        _changed();
      } while (_countsDirty && !_disposed);
    } catch (_) {
      // Counters are cosmetic.
    } finally {
      _countsBusy = false;
    }
  }

  void _onEvent(SyncEvent e) {
    switch (e) {
      case SyncPhaseEvent():
        if (!_running) {
          _running = true;
          _bytes = 0;
          _bytesTotal = 0;
          _lastError = null;
        }
        _phase = e.phase;
      case SyncProgressEvent():
        if (!_running) _running = true;
        _bytes = e.bytesTransferred;
        _bytesTotal = e.bytesTotal;
      case SyncDoneEvent():
        _running = false;
        _phase = null;
        _lastReport = e.report;
        _lastError = null;
        _refreshCounts();
      case SyncFailedEvent():
        _running = false;
        _phase = null;
        _lastError = e.error;
        _refreshCounts();
    }
    _changed();
  }

  void setMirror(bool value) {
    if (_mirror == value) return;
    _mirror = value;
    onMirrorChanged?.call(value);
    _changed();
  }

  /// Phone only. No-op when a sync cannot start right now.
  void syncNow() {
    final engine = _engine;
    if (engine == null || !canSyncNow) return;
    _lastError = null;
    try {
      engine.startSync(mirrorDictionaries: _mirror);
    } on StateError {
      return;
    }
    _changed();
  }

  /// Cancels the running sync (either role).
  void cancel() {
    _engine?.activeSession?.cancel();
  }

  Future<void> runCheck() async {
    final check = _check;
    if (check == null || !canRunCheck) return;
    _checkRunning = true;
    _checkResult = null;
    _checkStage = SyncCheckStage.ping;
    _changed();
    try {
      final r = await check.run(
        onStage: (s) {
          _checkStage = s;
          _changed();
        },
      );
      _checkResult = r;
    } catch (_) {
      // Disposed mid-run.
    }
    _checkRunning = false;
    _checkStage = null;
    _changed();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _eventSub?.cancel();
    _peerSub?.cancel();
    _cardSub?.cancel();
    _dictSub?.cancel();
    final engine = _engine;
    final check = _check;
    final base = _base;
    () async {
      try {
        await check?.dispose();
        await engine?.dispose();
        await base?.dispose();
      } catch (_) {}
    }();
    super.dispose();
  }
}
