import 'dart:async';

import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_selection.dart';
import 'package:chameleonultragui/wear/features/read/read_effects.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:flutter/foundation.dart';

/// Which of the four menu entries a read page runs.
enum ReadMode {
  hf,
  lf,
  scanHf,
  scanLf;

  bool get isHf => this == hf || this == scanHf;
  bool get isContinuous => this == scanHf || this == scanLf;
}

/// What the read page shows right now.
enum ReadStage {
  /// Loading dictionaries / waiting for the first event.
  preparing,

  /// Field on, waiting for a card.
  scanning,

  /// A card answered and the first checks run.
  identifying,
  checkingKeys,
  recovering,
  dumping,

  /// Finished with a card; [ReadController.hf] or [ReadController.lf] is set.
  result,

  /// Finished, nothing in the field.
  noCard,

  /// Terminal failure; see [ReadController.error].
  failed,

  /// Stopped by the user, or a continuous scan ran out of time.
  stopped,
}

/// Drives one [ReadSession] at a time and exposes its progress as plain state
/// for the read page. Cancels everything on [dispose], so nothing keeps
/// talking to the Chameleon after the page is gone.
class ReadController extends ChangeNotifier {
  ReadController({
    required this.services,
    required this.mode,
    this.effects = const ReadEffects(),
    this.scanInterval = const Duration(seconds: 1),
    this.scanMaxDuration = const Duration(minutes: 5),
  });

  final WearServices services;
  final ReadMode mode;
  final ReadEffects effects;
  final Duration scanInterval;
  final Duration scanMaxDuration;

  ReadStage _stage = ReadStage.preparing;
  ReadStage get stage => _stage;

  /// 1-based attempt of a continuous scan.
  int attempt = 1;

  /// Card seen in the current/last run (HF) and LF id.
  CardData? hfCard;
  LFCard? lfCard;

  ReadCheckingKeys? keyCheck;
  ReadRecoveryProgress? recovery;
  ReadDumpProgress? dumpProgress;

  /// Last finished HF/LF result (kept while a follow-up step runs or fails).
  HfReadResult? hf;
  LfReadResult? lf;

  /// Set in [ReadStage.failed].
  ReadErrorCode? error;

  /// True when a continuous scan ended because the time cap elapsed.
  bool timedOut = false;

  /// The Mifare Classic step that failed, for "Retry".
  MifareClassicDepth? _failedStep;
  MifareClassicDepth? get failedStep => _failedStep;

  ReadSession? _session;
  StreamSubscription<ReadEvent>? _sub;
  int _generation = 0;
  bool _disposed = false;
  bool _awake = false;

  /// True while a session is running.
  bool get busy => switch (_stage) {
    ReadStage.preparing ||
    ReadStage.scanning ||
    ReadStage.identifying ||
    ReadStage.checkingKeys ||
    ReadStage.recovering ||
    ReadStage.dumping => true,
    _ => false,
  };

  /// Starts (or restarts) the read of this controller's [mode].
  Future<void> start() async {
    final gen = await _beginRun();
    if (gen == null) return;
    hf = null;
    lf = null;
    hfCard = null;
    lfCard = null;
    final service = services.readService;
    if (service == null) return _fail(ReadErrorCode.notConnected);
    try {
      ReadSession session;
      if (mode.isHf) {
        final options = await _hfOptions(MifareClassicDepth.identify);
        if (_stale(gen)) return;
        session = mode.isContinuous
            ? service.startContinuousHfScan(options: _scanOptions(options))
            : service.readHf(options: options);
      } else {
        session = mode.isContinuous
            ? service.startContinuousLfScan(options: _scanOptions())
            : service.readLf();
      }
      _attach(session, gen);
    } catch (e) {
      if (!_stale(gen)) _fail(ReadErrorCode.unknown);
    }
  }

  /// Continues the Mifare Classic read of [hf] up to [depth].
  Future<void> continueMifare(MifareClassicDepth depth) async {
    final state = hf?.mifareClassic;
    if (state == null) return;
    final gen = await _beginRun(keepResult: true);
    if (gen == null) return;
    _failedStep = depth;
    final service = services.readService;
    if (service == null) return _fail(ReadErrorCode.notConnected);
    try {
      final options = await _hfOptions(depth);
      if (_stale(gen)) return;
      _stage = switch (depth) {
        MifareClassicDepth.dump => ReadStage.dumping,
        MifareClassicDepth.recoverKeys => ReadStage.recovering,
        _ => ReadStage.checkingKeys,
      };
      notifyListeners();
      _attach(
        service.continueMifareClassic(state, depth: depth, options: options),
        gen,
      );
    } catch (e) {
      if (!_stale(gen)) _fail(ReadErrorCode.unknown);
    }
  }

  /// Cancels the running session (the Stop / Cancel button).
  Future<void> stop() async {
    final s = _session;
    if (s == null || s.isFinished) return;
    await s.cancel();
  }

  /// Leaves the failed state and shows the last good result again.
  void backToResult() {
    if (hf == null && lf == null) return;
    error = null;
    _failedStep = null;
    _stage = ReadStage.result;
    notifyListeners();
  }

  // ---- internals ---------------------------------------------------------

  Future<HfReadOptions> _hfOptions(MifareClassicDepth depth) async {
    final dictionaries = await WearDictionarySelection.active(services);
    return HfReadOptions(
      depth: depth,
      dictionaries: dictionaries,
      // The watch cannot run hardnested (it needs ~1.2 GB and crashes it).
      allowHardnested: false,
    );
  }

  ContinuousScanOptions _scanOptions([HfReadOptions? hfOptions]) =>
      ContinuousScanOptions(
        interval: scanInterval,
        maxDuration: scanMaxDuration,
        hf: hfOptions ?? const HfReadOptions(allowHardnested: false),
      );

  bool _stale(int gen) => _disposed || gen != _generation;

  /// Cancels any running session, resets progress state and returns the new
  /// generation, or null when disposed meanwhile.
  Future<int?> _beginRun({bool keepResult = false}) async {
    final gen = ++_generation;
    await _teardown();
    if (_stale(gen)) return null;
    keyCheck = null;
    recovery = null;
    dumpProgress = null;
    error = null;
    timedOut = false;
    attempt = 1;
    if (!keepResult) _failedStep = null;
    _stage = ReadStage.preparing;
    notifyListeners();
    if (mode.isContinuous && !keepResult) await _keepAwake(true);
    return _stale(gen) ? null : gen;
  }

  Future<void> _teardown() async {
    final sub = _sub;
    final session = _session;
    _sub = null;
    _session = null;
    unawaited(sub?.cancel());
    if (session != null && !session.isFinished) {
      try {
        await session.cancel();
        await session.terminal;
      } catch (_) {}
    }
  }

  void _attach(ReadSession session, int gen) {
    _session = session;
    _sub = session.events.listen(
      (e) {
        if (!_stale(gen)) _onEvent(e);
      },
      onError: (_) {
        if (!_stale(gen)) _fail(ReadErrorCode.unknown);
      },
    );
  }

  void _onEvent(ReadEvent e) {
    switch (e) {
      case ReadScanning():
        attempt = e.attempt;
        _stage = ReadStage.scanning;
      case ReadCardDetected():
        hfCard = e.hfCard;
        lfCard = e.lfCard;
        _stage = ReadStage.identifying;
        if (mode.isContinuous) unawaited(effects.hapticFound());
      case ReadCheckingKeys():
        keyCheck = e;
        _stage = ReadStage.checkingKeys;
      case ReadRecoveryProgress():
        recovery = e;
        _stage = ReadStage.recovering;
      case ReadDumpProgress():
        dumpProgress = e;
        _stage = ReadStage.dumping;
      case ReadDone():
        _finish(e.result);
      case ReadFailed():
        _fail(e.code);
        return;
      case ReadCancelled():
        timedOut = e.timedOut;
        _stage = (hf != null || lf != null)
            ? ReadStage.result
            : ReadStage.stopped;
        _endRun();
    }
    notifyListeners();
  }

  void _finish(ReadResult result) {
    switch (result) {
      case HfReadResult():
        // A continued Mifare Classic read carries no card data of its own.
        final previous = hf;
        final merged = result.card == null && previous?.card != null
            ? HfReadResult(
                card: previous!.card,
                type: result.type == TagType.unknown
                    ? previous.type
                    : result.type,
                mifareClassic: result.mifareClassic,
                mifareUltralight: result.mifareUltralight,
              )
            : result;
        hf = merged;
        _stage = merged.cardPresent ? ReadStage.result : ReadStage.noCard;
      case LfReadResult():
        lf = result;
        _stage = result.cardPresent ? ReadStage.result : ReadStage.noCard;
    }
    _failedStep = null;
    _endRun();
  }

  void _fail(ReadErrorCode code) {
    error = code;
    _stage = ReadStage.failed;
    _endRun();
    notifyListeners();
  }

  void _endRun() {
    _session = null;
    unawaited(_keepAwake(false));
  }

  Future<void> _keepAwake(bool on) async {
    if (_awake == on) return;
    _awake = on;
    await effects.setKeepAwake(on);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    final sub = _sub;
    final session = _session;
    _sub = null;
    _session = null;
    sub?.cancel();
    if (session != null && !session.isFinished) {
      unawaited(session.cancel().catchError((_) {}));
    }
    if (_awake) {
      _awake = false;
      unawaited(effects.setKeepAwake(false));
    }
    super.dispose();
  }
}
