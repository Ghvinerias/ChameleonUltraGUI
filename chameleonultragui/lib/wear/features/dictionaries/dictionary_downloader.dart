import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/models/dictionary.dart';
import 'package:http/http.dart' as http;

/// A downloadable dictionary. Same list as the phone app
/// (lib/gui/menu/tools/dictionary_download.dart, which cannot be imported
/// without pulling in the whole phone UI).
class DictionarySource {
  const DictionarySource(this.name, this.url);
  final String name;
  final String url;
}

const kDictionarySources = <DictionarySource>[
  DictionarySource(
    'Proxmark3 (Mifare Classic)',
    'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/mfc_default_keys.dic',
  ),
  DictionarySource(
    'Proxmark3 (T55XX)',
    'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/t55xx_default_pwds.dic',
  ),
  DictionarySource(
    'Proxmark3 (Mifare Ultralight C)',
    'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/mfulc_default_keys.dic',
  ),
  DictionarySource(
    'Proxmark3 (Mifare Plus)',
    'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/mfp_default_keys.dic',
  ),
  DictionarySource(
    'Flipper Zero Unleashed Firmware (Mifare Classic)',
    'https://raw.githubusercontent.com/DarkFlippers/unleashed-firmware/refs/heads/dev/applications/main/nfc/resources/nfc/assets/mf_classic_dict.nfc',
  ),
];

const kMaxDownloadBytes = 2 * 1024 * 1024;

enum DownloadFailure {
  noNetwork,
  timeout,
  httpError,
  tooLarge,
  malformed,
  duplicate,
  cancelled,
  other,
}

sealed class DownloadResult {
  const DownloadResult();
}

class DownloadSuccess extends DownloadResult {
  const DownloadSuccess(this.dictionary);
  final Dictionary dictionary;
}

class DownloadFailed extends DownloadResult {
  const DownloadFailed(this.failure, {this.statusCode});
  final DownloadFailure failure;
  final int? statusCode;
}

/// Cancels a running [DictionaryDownloader.download].
class DownloadCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  final _listeners = <void Function()>[];

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }
}

/// Downloads and parses a dictionary. Never throws; failures are results.
///
/// Parsing is the phone's `Dictionary.fromString`. The caller decides about
/// duplicates and persistence (see `DictionaryDownloader.isDuplicate`).
class DictionaryDownloader {
  DictionaryDownloader({
    this.client,
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = kMaxDownloadBytes,
  });

  /// Injected client (tests). When null a client is created per download
  /// and closed on completion or cancel.
  final http.Client? client;
  final Duration timeout;
  final int maxBytes;

  /// [onProgress] gets (received bytes, total bytes or null).
  Future<DownloadResult> download(
    DictionarySource source, {
    DownloadCancel? cancel,
    void Function(int received, int? total)? onProgress,
  }) async {
    final owned = client == null;
    final c = client ?? http.Client();
    final cancelled = Completer<DownloadResult>();
    cancel?._listeners.add(() {
      if (!cancelled.isCompleted) {
        cancelled.complete(const DownloadFailed(DownloadFailure.cancelled));
      }
      if (owned) c.close();
    });
    try {
      return await Future.any([
        _run(c, source, cancel, onProgress),
        cancelled.future,
      ]).timeout(timeout);
    } on TimeoutException {
      return const DownloadFailed(DownloadFailure.timeout);
    } on SocketException {
      return _cancelledOr(cancel, DownloadFailure.noNetwork);
    } on http.ClientException {
      return _cancelledOr(cancel, DownloadFailure.noNetwork);
    } catch (_) {
      return _cancelledOr(cancel, DownloadFailure.other);
    } finally {
      if (owned) c.close();
    }
  }

  DownloadResult _cancelledOr(DownloadCancel? cancel, DownloadFailure f) =>
      DownloadFailed(
        (cancel?.isCancelled ?? false) ? DownloadFailure.cancelled : f,
      );

  Future<DownloadResult> _run(
    http.Client c,
    DictionarySource source,
    DownloadCancel? cancel,
    void Function(int, int?)? onProgress,
  ) async {
    final response = await c.send(http.Request('GET', Uri.parse(source.url)));
    if (response.statusCode != 200) {
      return DownloadFailed(
        DownloadFailure.httpError,
        statusCode: response.statusCode,
      );
    }
    final total = response.contentLength;
    if (total != null && total > maxBytes) {
      return const DownloadFailed(DownloadFailure.tooLarge);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (cancel?.isCancelled ?? false) {
        return const DownloadFailed(DownloadFailure.cancelled);
      }
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        return const DownloadFailed(DownloadFailure.tooLarge);
      }
      onProgress?.call(bytes.length, total);
    }
    if (cancel?.isCancelled ?? false) {
      return const DownloadFailed(DownloadFailure.cancelled);
    }
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    final dict = Dictionary.fromString(text, name: source.name);
    if (dict.keys.isEmpty) {
      return const DownloadFailed(DownloadFailure.malformed);
    }
    return DownloadSuccess(dict);
  }

  /// True when [existing] already holds a dictionary with the same keys
  /// (same length, same order).
  static bool isDuplicate(Dictionary candidate, Iterable<Dictionary> existing) {
    final sig = _signature(candidate);
    return existing.any((d) => _signature(d) == sig);
  }

  static String _signature(Dictionary d) =>
      '${d.keyLength}:${d.keys.map((k) => k.map((b) => b.toRadixString(16).padLeft(2, '0')).join()).join(',')}';
}
