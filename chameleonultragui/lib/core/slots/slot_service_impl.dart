import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/core/slots/slot_service.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf14a4_slot.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/models/card_save.dart';

/// [SlotService] on top of a [ChameleonCommunicator]. The command sequences
/// are the ones `slot_manager.dart` used to issue inline.
class SlotServiceImpl implements SlotService {
  final ChameleonCommunicator _communicator;

  SlotServiceImpl(this._communicator);

  @override
  bool canUpload(CardSave card) => _kind(card.tag) != null;

  static _Kind? _kind(TagType tag) {
    if (isMifareClassic(tag)) return _Kind.mfc;
    if (tag == TagType.hf14a4) return _Kind.hf14a4;
    if (isEM410X(tag)) return _Kind.em410x;
    if (tag == TagType.hidProx ||
        tag == TagType.viking ||
        tag == TagType.pac ||
        tag == TagType.ioProx ||
        tag == TagType.idteck) {
      return _Kind.lf;
    }
    if (isMifareUltralight(tag)) return _Kind.mfu;
    return null;
  }

  @override
  SlotUpload uploadCard(
    CardSave card,
    int slot, {
    String emptyNameFallback = '',
  }) {
    final upload = _SlotUploadImpl();
    upload._start(() => _run(upload, _copy(card), slot, emptyNameFallback));
    return upload;
  }

  /// Shallow copy with a fresh list/extra so the caller's card is untouched
  /// (blocks themselves are never modified).
  static CardSave _copy(CardSave c) => CardSave(
    id: c.id,
    uid: c.uid,
    name: c.name,
    tag: c.tag,
    sak: c.sak,
    atqa: c.atqa,
    ats: c.ats,
    extraData: CardSaveExtra(
      ultralightSignature: c.extraData.ultralightSignature,
      ultralightVersion: c.extraData.ultralightVersion,
      ultralightCounters: List<int>.of(c.extraData.ultralightCounters),
    ),
    color: c.color,
    folderId: c.folderId,
    updatedAt: c.updatedAt,
    data: List<Uint8List>.of(c.data),
  );

  Future<void> _run(
    _SlotUploadImpl up,
    CardSave card,
    int slot,
    String fallback,
  ) async {
    final kind = _kind(card.tag);
    if (kind == null) {
      throw const _SlotFailure(SlotErrorCode.unsupportedCardType);
    }
    if (slot < 0 || slot >= SlotService.slotCount) {
      throw const _SlotFailure(SlotErrorCode.invalidSlot);
    }

    final c = _communicator;
    final isHf = kind == _Kind.mfc || kind == _Kind.hf14a4 || kind == _Kind.mfu;
    final frequency = isHf ? TagFrequency.hf : TagFrequency.lf;
    var tag = card.tag;
    if (kind == _Kind.mfc && chameleonTagSaveCheckForMifareClassicEV1(card)) {
      tag = TagType.mifare2K;
      card.tag = tag;
    }
    if (kind == _Kind.em410x && tag != TagType.em410XElectra) {
      tag = TagType.em410X;
    }

    await up._step(() => c.setReaderDeviceMode(false));
    await up._step(() => c.enableSlot(slot, frequency, true));
    await up._step(() => c.activateSlot(slot));
    await up._step(() => c.setSlotType(slot, tag));
    await up._step(() => c.setDefaultDataToSlot(slot, tag));

    switch (kind) {
      case _Kind.mfc:
        await up._step(() => c.setMf1AntiCollision(_identity(card)));
        up._emit(SlotUploadStarted(slot));
        await _writeMfcBlocks(up, card, tag);
        up._progress(100);
      case _Kind.hf14a4:
        await up._step(() => writeHf14a4SlotIdentity(c, card));
        up._emit(SlotUploadStarted(slot));
        up._progress(100);
      case _Kind.mfu:
        await up._step(() => c.setMf1AntiCollision(_identity(card)));
        up._emit(SlotUploadStarted(slot));
        await _writeUltralight(up, card);
        up._progress(100);
      case _Kind.em410x:
        up._emit(SlotUploadStarted(slot));
        await up._step(() => c.setEM410XEmulatorID(hexToBytes(card.uid)));
      case _Kind.lf:
        up._emit(SlotUploadStarted(slot));
        await up._step(() => _setLfId(card));
    }

    final name = card.name.isEmpty ? fallback : card.name;
    await up._step(() => c.setSlotTagName(slot, name, frequency));
    await up._step(() => c.saveSlotData());
    up._finish(SlotUploadDone(slot));
  }

  CardData _identity(CardSave card) => CardData(
    uid: hexToBytes(card.uid),
    atqa: card.atqa,
    sak: card.sak,
    ats: card.ats,
  );

  Future<void> _setLfId(CardSave card) {
    final c = _communicator;
    switch (card.tag) {
      case TagType.hidProx:
        return c.setHIDProxEmulatorID(
          hexToBytes(HIDCard.fromUID(card.uid).toString()),
        );
      case TagType.viking:
        return c.setVikingEmulatorID(hexToBytes(card.uid));
      case TagType.pac:
        return c.setPacEmulatorID(hexToBytes(card.uid));
      case TagType.ioProx:
        return c.setIoProxEmulatorID(hexToBytes(card.uid));
      default:
        return c.setIdteckEmulatorID(hexToBytes(card.uid));
    }
  }

  Future<void> _writeMfcBlocks(
    _SlotUploadImpl up,
    CardSave card,
    TagType tag,
  ) async {
    final blockCount = mfClassicGetBlockCount(
      chameleonTagTypeGetMfClassicType(tag),
    );
    final data = card.data;
    List<int> blockChunk = [];
    int lastSend = 0;

    for (var blockOffset = 0; blockOffset < blockCount; blockOffset++) {
      if ((data.length > blockOffset && data[blockOffset].isEmpty) ||
          blockChunk.length >= 128) {
        if (blockChunk.isNotEmpty) {
          final chunk = Uint8List.fromList(blockChunk);
          final start = lastSend;
          await up._step(() => _communicator.setMf1BlockData(start, chunk));
          blockChunk = [];
          lastSend = blockOffset;
        }
      }

      if (data.length > blockOffset && data[blockOffset].length == 16) {
        blockChunk.addAll(data[blockOffset]);
      }

      up._progress((blockOffset / blockCount * 100).round());
      await asyncSleep(1);
    }

    if (blockChunk.isNotEmpty) {
      final chunk = Uint8List.fromList(blockChunk);
      final start = lastSend;
      await up._step(() => _communicator.setMf1BlockData(start, chunk));
    }
  }

  Future<void> _writeUltralight(_SlotUploadImpl up, CardSave card) async {
    final c = _communicator;
    final pages = mfUltralightGetPagesCount(card.tag);

    for (var page = 0; page < pages && card.data.length > page; page++) {
      await up._step(() => c.mf0EmulatorWritePages(page, card.data[page]));
      up._progress((page / pages * 100).round());
      await asyncSleep(1);
    }

    final extra = card.extraData;
    if (extra.ultralightVersion.isNotEmpty) {
      await up._step(
        () => c.mf0EmulatorSetVersionData(extra.ultralightVersion),
      );
    }
    if (extra.ultralightSignature.isNotEmpty) {
      await up._step(
        () => c.mf0EmulatorSetSignatureData(extra.ultralightSignature),
      );
    }
    for (int i = 0; i < extra.ultralightCounters.length; i++) {
      await up._step(
        () => c.mf0EmulatorSetCounterData(i, extra.ultralightCounters[i], true),
      );
    }
    if (mfUltralightHasCounters(card.tag)) {
      await up._step(() => c.mf0ResetAuthCount());
    }
  }

  // ---- queries / updates -------------------------------------------------

  void _checkSlot(int slot) {
    if (slot < 0 || slot >= SlotService.slotCount) {
      throw ArgumentError.value(slot, 'slot', 'must be 0..7');
    }
  }

  @override
  Future<List<SlotInfo>> getSlots() async {
    final types = await _communicator.getSlotTagTypes();
    final enabled = await _communicator.getEnabledSlots();
    final names = await _communicator.getSlotTagNames();

    return List.generate(
      SlotService.slotCount,
      (i) => SlotInfo(
        index: i,
        hfType: types[i].hf,
        lfType: types[i].lf,
        hfEnabled: enabled[i].hf,
        lfEnabled: enabled[i].lf,
        hfName: names[i].hf,
        lfName: names[i].lf,
      ),
    );
  }

  @override
  Future<int> getActiveSlot() => _communicator.getActiveSlot();

  @override
  Future<void> activateSlot(int slot) {
    _checkSlot(slot);
    return _communicator.activateSlot(slot);
  }

  @override
  Future<void> setSlotEnabled(
    int slot,
    TagFrequency frequency,
    bool enabled,
  ) async {
    _checkSlot(slot);
    await _communicator.enableSlot(slot, frequency, enabled);
    await _communicator.saveSlotData();
  }

  @override
  Future<void> renameSlot(int slot, TagFrequency frequency, String name) async {
    _checkSlot(slot);
    await _communicator.setSlotTagName(slot, name, frequency);
    await _communicator.saveSlotData();
  }
}

enum _Kind { mfc, hf14a4, em410x, lf, mfu }

class _SlotFailure implements Exception {
  final SlotErrorCode code;

  const _SlotFailure(this.code);
}

class _SlotUploadImpl implements SlotUpload {
  final _controller = StreamController<SlotUploadEvent>.broadcast();
  final _terminal = Completer<SlotUploadEvent>();
  bool _cancelled = false;
  int _lastPercent = -1;

  @override
  Stream<SlotUploadEvent> get events => _controller.stream;

  @override
  Future<SlotUploadEvent> get terminal => _terminal.future;

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  void _start(Future<void> Function() body) {
    // Defer so the caller can attach listeners before the first event.
    Future<void>(() async {
      try {
        await body();
      } on _SlotFailure catch (e) {
        _finish(SlotUploadFailed(e.code));
      } catch (e) {
        _finish(
          SlotUploadFailed(SlotErrorCode.communication, detail: e.toString()),
        );
      }
    });
  }

  Future<void> _step(Future<void> Function() command) async {
    if (_cancelled) throw const _SlotFailure(SlotErrorCode.cancelled);
    await command();
  }

  void _emit(SlotUploadEvent e) {
    if (!_controller.isClosed) _controller.add(e);
  }

  void _progress(int percent) {
    if (percent == _lastPercent) return;
    _lastPercent = percent;
    _emit(SlotUploadProgress(percent));
  }

  void _finish(SlotUploadEvent e) {
    if (_terminal.isCompleted) return;
    _emit(e);
    _terminal.complete(e);
    _controller.close();
  }
}
