import 'package:chameleonultragui/wear/features/dictionaries/dictionary_downloader.dart';
import 'package:chameleonultragui/wear/features/dictionaries/dictionary_selection.dart';
import 'package:chameleonultragui/wear/features/dictionaries/strings.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:chameleonultragui/wear/theme/wear_theme.dart';
import 'package:chameleonultragui/wear/widgets/compact_list_tile.dart';
import 'package:chameleonultragui/wear/widgets/progress_ring.dart';
import 'package:chameleonultragui/wear/widgets/round_scaffold.dart';
import 'package:chameleonultragui/wear/widgets/status_pill.dart';
import 'package:chameleonultragui/wear/widgets/wear_button.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Pick a known dictionary URL, download, parse and save through the store.
class DictionaryDownloadPage extends StatefulWidget {
  const DictionaryDownloadPage({
    super.key,
    this.client,
    this.timeout = const Duration(seconds: 20),
  });

  final http.Client? client;
  final Duration timeout;

  @override
  State<DictionaryDownloadPage> createState() => _DictionaryDownloadPageState();
}

class _DictionaryDownloadPageState extends State<DictionaryDownloadPage> {
  DownloadCancel? _cancel;
  DictionarySource? _running;
  double? _progress;
  String? _message;
  StatusKind _kind = StatusKind.info;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _start(DictionarySource source) async {
    final services = WearServicesScope.of(context);
    final cancel = DownloadCancel();
    setState(() {
      _cancel = cancel;
      _running = source;
      _progress = null;
      _message = null;
    });
    final result =
        await DictionaryDownloader(
          client: widget.client,
          timeout: widget.timeout,
        ).download(
          source,
          cancel: cancel,
          onProgress: (received, total) {
            if (mounted && total != null && total > 0) {
              setState(() => _progress = received / total);
            }
          },
        );
    if (!mounted || cancel.isCancelled) return;

    String message;
    StatusKind kind = StatusKind.error;
    switch (result) {
      case DownloadSuccess(:final dictionary):
        final store = services.dictionaryStore;
        final existing = await store.getDictionaries();
        if (!mounted) return;
        if (DictionaryDownloader.isDuplicate(dictionary, existing)) {
          message = DictStrings.duplicate;
          kind = StatusKind.warning;
        } else {
          final saved = await store.saveDictionary(dictionary);
          // With an explicit selection, a download the user asked for is
          // used straight away (6-byte keys only).
          final sel = await WearDictionarySelection.selectedIds();
          if (sel != null && saved.keyLength == 12) {
            await WearDictionarySelection.setSelectedIds({...sel, saved.id});
          }
          message = DictStrings.saved(saved.name, saved.keys.length);
          kind = StatusKind.ok;
        }
      case DownloadFailed(:final failure, :final statusCode):
        message = switch (failure) {
          DownloadFailure.noNetwork => DictStrings.noNetwork,
          DownloadFailure.timeout => DictStrings.timeout,
          DownloadFailure.httpError => DictStrings.httpError(statusCode ?? 0),
          DownloadFailure.tooLarge => DictStrings.tooLarge(kMaxDownloadBytes),
          DownloadFailure.malformed => DictStrings.malformed,
          DownloadFailure.duplicate => DictStrings.duplicate,
          DownloadFailure.cancelled => DictStrings.cancelled,
          DownloadFailure.other => DictStrings.failed,
        };
    }
    if (!mounted) return;
    setState(() {
      _running = null;
      _cancel = null;
      _message = message;
      _kind = kind;
    });
  }

  void _abort() {
    _cancel?.cancel();
    setState(() {
      _running = null;
      _cancel = null;
      _message = DictStrings.cancelled;
      _kind = StatusKind.neutral;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_running != null) {
      return RoundScaffold(
        title: DictStrings.downloading,
        children: [
          Center(
            child: ProgressRing(
              value: _progress,
              size: 96,
              strokeWidth: 8,
              child: _progress == null
                  ? const SizedBox.shrink()
                  : Text(
                      '${(_progress! * 100).round()}%',
                      style: theme.textTheme.titleMedium,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _running!.name,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          WearButton(
            label: DictStrings.cancel,
            style: WearButtonStyle.tonal,
            onPressed: _abort,
          ),
        ],
      );
    }
    return RoundScaffold(
      title: DictStrings.downloadTitle,
      children: [
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Center(
              child: StatusPill(label: _message!, kind: _kind),
            ),
          ),
        for (final s in kDictionarySources)
          CompactListTile(
            title: s.name,
            leading: const Icon(Icons.cloud_download_outlined),
            onTap: () => _start(s),
          ),
        const SizedBox(height: 4),
        Text(
          DictStrings.syncHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: WearColors.muted),
        ),
      ],
    );
  }
}
