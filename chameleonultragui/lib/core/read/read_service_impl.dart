import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/core/read/key_recovery_backend.dart';
import 'package:chameleonultragui/core/read/mifare_classic_engine.dart';
import 'package:chameleonultragui/core/read/native_key_recovery_backend.dart';
import 'package:chameleonultragui/core/read/read_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:logger/logger.dart';

/// Thrown by helpers that wrap a session when it ends with [ReadFailed].
class ReadFailedException implements Exception {
  final ReadErrorCode code;
  final String? detail;

  const ReadFailedException(this.code, [this.detail]);

  @override
  String toString() => 'ReadFailedException($code, $detail)';
}

class _CardLost implements Exception {
  final Object cause;

  const _CardLost(this.cause);
}

/// [ReadService] on top of a [ChameleonCommunicator]. No BuildContext, no
/// Provider, no localization.
class ReadServiceImpl implements ReadService {
  final ChameleonCommunicator communicator;
  final KeyRecoveryBackend backend;
  final Logger? log;

  /// Keys per `mf1AuthMultipleKeys` command: 32 over BLE, 64 over USB.
  final int keyChunkSize;

  /// Wall clock used for the continuous-scan cap (injectable for tests).
  final DateTime Function() now;

  _ReadSession? _active;

  ReadServiceImpl({
    required this.communicator,
    this.backend = const NativeKeyRecoveryBackend(),
    this.log,
    this.keyChunkSize = 32,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  ReadSession _start(
    Future<ReadEvent> Function(_ReadSession session) body,
  ) {
    if (_active != null && !_active!.isFinished) {
      throw StateError('A read session is already running on this device');
    }
    final session = _ReadSession(this, body);
    _active = session;
    return session;
  }

  @override
  ReadSession readHf({HfReadOptions options = const HfReadOptions()}) =>
      _start((s) async {
        final attempt = await _readHfOnce(s, options, 1);
        return ReadDone(attempt);
      });

  @override
  ReadSession readLf() => _start((s) async {
    final card = await _readLfOnce(s, 1);
    return ReadDone(LfReadResult(card: card));
  });

  @override
  ReadSession continueMifareClassic(
    MifareClassicReadState from, {
    required MifareClassicDepth depth,
    HfReadOptions options = const HfReadOptions(),
  }) => _start((s) async {
    final state = await _continueMfc(s, from, depth, options);
    return ReadDone(
      HfReadResult(
        type: mfClassicGetChameleonTagType(state.type),
        mifareClassic: state,
      ),
    );
  });

  @override
  ReadSession startContinuousHfScan({
    ContinuousScanOptions options = const ContinuousScanOptions(),
  }) => _start(
    (s) => _continuous(
      s,
      options,
      (attempt) async {
        try {
          final result = await _readHfOnce(s, options.hf, attempt);
          return result.cardPresent ? result : null;
        } on _CardLost {
          return null; // same as the phone: not a card yet, keep scanning
        }
      },
      (found) => ReadDone(found as HfReadResult),
    ),
  );

  @override
  ReadSession startContinuousLfScan({
    ContinuousScanOptions options = const ContinuousScanOptions(),
  }) => _start(
    (s) => _continuous(
      s,
      options,
      (attempt) async {
        final card = await _readLfOnce(s, attempt);
        return card == null ? null : LfReadResult(card: card);
      },
      (found) => ReadDone(found as LfReadResult),
    ),
  );

  // ---- continuous ---------------------------------------------------------

  Future<ReadEvent> _continuous(
    _ReadSession s,
    ContinuousScanOptions options,
    Future<ReadResult?> Function(int attempt) probe,
    ReadEvent Function(ReadResult found) done,
  ) async {
    final start = now();
    var attempt = 0;
    while (true) {
      attempt++;
      final found = await probe(attempt);
      if (found != null && options.stopOnFound) {
        return done(found);
      }
      await s.sleep(options.interval);
      if (now().difference(start) >= options.maxDuration) {
        return const ReadCancelled(timedOut: true);
      }
    }
  }

  // ---- LF -----------------------------------------------------------------

  Future<LFCard?> _readLfOnce(_ReadSession s, int attempt) async {
    s.emit(ReadScanning(ReadFrequency.lf, attempt: attempt));
    s.check();
    if (!await communicator.isReaderDeviceMode()) {
      s.check();
      await communicator.setReaderDeviceMode(true);
    }

    LFCard? card;
    final probes = <Future<LFCard?> Function()>[
      communicator.readEM410X,
      communicator.readHIDProx,
      communicator.readViking,
      communicator.readPac,
      communicator.readIoProx,
    ];
    for (final probe in probes) {
      s.check();
      card = await probe();
      if (card != null) break;
    }

    if (card != null) {
      s.emit(ReadCardDetected(ReadFrequency.lf, lfCard: card));
    }
    return card;
  }

  // ---- HF -----------------------------------------------------------------

  Future<HfReadResult> _readHfOnce(
    _ReadSession s,
    HfReadOptions options,
    int attempt,
  ) async {
    s.emit(ReadScanning(ReadFrequency.hf, attempt: attempt));
    s.check();
    if (!await communicator.isReaderDeviceMode()) {
      s.check();
      await communicator.setReaderDeviceMode(true);
    }

    s.check();
    final CardData? card = await communicator.scan14443aTag();
    if (card == null) {
      return const HfReadResult();
    }
    s.emit(ReadCardDetected(ReadFrequency.hf, hfCard: card));

    TagType type = TagType.unknown;
    MifareClassicReadState? mfc;
    MifareUltralightReadState? mfu;
    try {
      s.check();
      if (!await communicator.detectMf1Support()) {
        final info = await mfUltralightIdentify(communicator);
        type = info.type;
        mfu = MifareUltralightReadState(
          version: info.version,
          signature: info.signature,
        );
      } else {
        s.check();
        final identity = await identifyMifareClassic(communicator);
        type = mfClassicGetChameleonTagType(identity.type);
        final engine = _engine(s, options, identity.type, identity.isEV1);
        engine.initializeEV1();
        mfc = _toState(
          engine,
          ntLevel: identity.ntLevel,
          hasBackdoor: identity.hasBackdoor,
          depth: MifareClassicDepth.identify,
        );
      }
    } on ReadCancelledSignal {
      rethrow;
    } catch (e) {
      log?.e(e.toString());
      throw _CardLost(e);
    }

    if (mfc != null && options.depth != MifareClassicDepth.identify) {
      mfc = await _continueMfc(s, mfc, options.depth, options);
    }

    return HfReadResult(
      card: card,
      type: type,
      mifareClassic: mfc,
      mifareUltralight: mfu,
    );
  }

  // ---- Mifare Classic steps -----------------------------------------------

  MifareClassicEngine _engine(
    _ReadSession s,
    HfReadOptions options,
    MifareClassicType type,
    bool isEV1, {
    List<SectorKeyState>? checkMarks,
    List<Uint8List>? validKeys,
    List<Uint8List>? cardData,
  }) => MifareClassicEngine(
    communicator: communicator,
    backend: backend,
    log: log,
    type: type,
    isEV1: isEV1,
    keyChunkSize: keyChunkSize,
    allowHardnested: options.allowHardnested,
    checkMarks: checkMarks ?? MifareClassicEngine.newCheckMarks(),
    validKeys: validKeys ?? MifareClassicEngine.newKeys(),
    cardData: cardData ?? MifareClassicEngine.newCardData(),
    emit: s.emit,
    isCancelled: () => s.cancelRequested,
  );

  MifareClassicReadState _toState(
    MifareClassicEngine engine, {
    required MifareClassicDepth depth,
    NTLevel? ntLevel,
    bool? hasBackdoor,
  }) {
    final states = List<SectorKeyState>.filled(80, SectorKeyState.none);
    final keys = List<Uint8List>.generate(80, (_) => Uint8List(0));
    for (var sector = 0; sector < 40; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        states[sector * 2 + keyType] = engine.checkMarks[sector + keyType * 40];
        keys[sector * 2 + keyType] = Uint8List.fromList(
          engine.validKeys[sector + keyType * 40],
        );
      }
    }
    return MifareClassicReadState(
      type: engine.type,
      isEV1: engine.isEV1,
      ntLevel: ntLevel,
      hasBackdoor: hasBackdoor,
      sectorStates: states,
      keys: keys,
      blocks: engine.cardData.map(Uint8List.fromList).toList(),
      allKeysFound: engine.allKeysExists,
      completedDepth: depth,
    );
  }

  List<Uint8List> _keyList(HfReadOptions options) {
    final dictionaries = <Dictionary>[...options.dictionaries];
    final primaryId = options.primaryDictionaryId;
    if (primaryId != null) {
      final index = dictionaries.indexWhere((d) => d.id == primaryId);
      if (index > 0) dictionaries.insert(0, dictionaries.removeAt(index));
    }
    return [
      for (final dictionary in dictionaries) ...dictionary.keys,
      if (!options.skipDefaultDictionary) ...gMifareClassicKeys,
    ];
  }

  Future<MifareClassicReadState> _continueMfc(
    _ReadSession s,
    MifareClassicReadState from,
    MifareClassicDepth depth,
    HfReadOptions options,
  ) async {
    final states = List<SectorKeyState>.filled(80, SectorKeyState.none);
    final keys = List<Uint8List>.generate(80, (_) => Uint8List(0));
    for (var i = 0; i < 80 && i < from.sectorStates.length; i++) {
      final index = (i % 2) * 40 + i ~/ 2;
      states[index] = from.sectorStates[i];
      keys[index] = Uint8List.fromList(from.keys[i]);
    }
    final blocks = List<Uint8List>.generate(
      256,
      (i) => i < from.blocks.length
          ? Uint8List.fromList(from.blocks[i])
          : Uint8List(0),
    );
    final engine = _engine(
      s,
      options,
      from.type,
      from.isEV1,
      checkMarks: states,
      validKeys: keys,
      cardData: blocks,
    )..allKeysExists = from.allKeysFound;

    var completed = from.completedDepth;
    MifareClassicReadState snapshot() => _toState(
      engine,
      depth: completed,
      ntLevel: from.ntLevel,
      hasBackdoor: from.hasBackdoor,
    );

    try {
      if (depth.index >= MifareClassicDepth.checkKeys.index &&
          completed.index < MifareClassicDepth.checkKeys.index) {
        await engine.checkKeys(_keyList(options));
        completed = MifareClassicDepth.checkKeys;
      }

      if (depth.index >= MifareClassicDepth.recoverKeys.index &&
          completed.index < MifareClassicDepth.recoverKeys.index) {
        if (!engine.allKeysExists) {
          final failure = await engine.recoverKeys();
          if (failure != null) {
            throw ReadFailedException(failure.code, failure.detail);
          }
        }
        completed = MifareClassicDepth.recoverKeys;
      }

      if (depth.index >= MifareClassicDepth.dump.index &&
          completed.index < MifareClassicDepth.dump.index) {
        try {
          await engine.dumpData();
        } on ReadCancelledSignal {
          rethrow;
        } on ReadFailedException {
          rethrow;
        } catch (e) {
          throw ReadFailedException(ReadErrorCode.dumpFailed, e.toString());
        }
        completed = MifareClassicDepth.dump;
      }
    } on KeyRecoveryUnavailableException catch (e) {
      throw ReadFailedException(
        ReadErrorCode.recoveryUnavailable,
        e.toString(),
      );
    }

    return snapshot();
  }
}

/// Sync-broadcast event stream plus cancellation plumbing for one run.
class _ReadSession implements ReadSession {
  final StreamController<ReadEvent> _controller =
      StreamController<ReadEvent>.broadcast(sync: true);
  final Completer<ReadEvent> _terminal = Completer<ReadEvent>();
  final ReadServiceImpl _service;
  bool _finished = false;
  bool _cancelRequested = false;
  Timer? _sleepTimer;
  Completer<void>? _sleeping;

  _ReadSession(
    this._service,
    Future<ReadEvent> Function(_ReadSession session) body,
  ) {
    // Start after the caller had a chance to listen: events are not replayed.
    scheduleMicrotask(() => _run(body));
  }

  bool get cancelRequested => _cancelRequested;

  @override
  Stream<ReadEvent> get events => _controller.stream;

  @override
  Future<ReadEvent> get terminal => _terminal.future;

  @override
  bool get isFinished => _finished;

  @override
  Future<void> cancel() async {
    if (_finished) return;
    _cancelRequested = true;
    _sleepTimer?.cancel();
    final sleeping = _sleeping;
    if (sleeping != null && !sleeping.isCompleted) sleeping.complete();
    await _terminal.future;
  }

  void emit(ReadEvent event) {
    if (!_finished && !_controller.isClosed) _controller.add(event);
  }

  /// Throws [ReadCancelledSignal] when [cancel] was requested.
  void check() {
    if (_cancelRequested) throw const ReadCancelledSignal();
  }

  /// Interruptible delay.
  Future<void> sleep(Duration duration) {
    check();
    final completer = Completer<void>();
    _sleeping = completer;
    _sleepTimer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future.then((_) {
      _sleeping = null;
      check();
    });
  }

  Future<void> _run(Future<ReadEvent> Function(_ReadSession session) body) async {
    ReadEvent terminal;
    try {
      terminal = await body(this);
    } on ReadCancelledSignal {
      terminal = const ReadCancelled();
    } on _CardLost catch (e) {
      terminal = ReadFailed(ReadErrorCode.cardLost, detail: e.cause.toString());
    } on ReadFailedException catch (e) {
      terminal = ReadFailed(e.code, detail: e.detail);
    } on KeyRecoveryUnavailableException catch (e) {
      terminal = ReadFailed(
        ReadErrorCode.recoveryUnavailable,
        detail: e.toString(),
      );
    } on TimeoutException catch (e) {
      terminal = ReadFailed(ReadErrorCode.timeout, detail: e.toString());
    } on Exception catch (e) {
      terminal = ReadFailed(ReadErrorCode.communication, detail: e.toString());
    } catch (e) {
      terminal = ReadFailed(ReadErrorCode.unknown, detail: e.toString());
    }
    _finish(terminal);
  }

  void _finish(ReadEvent terminal) {
    if (_finished) return;
    _controller.add(terminal);
    _finished = true;
    if (identical(_service._active, this)) _service._active = null;
    _terminal.complete(terminal);
    _controller.close();
  }
}
