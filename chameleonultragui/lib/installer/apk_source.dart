import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'watch_installer.dart';

/// Provides the watch APK as a local file path.
abstract class ApkFetcher {
  /// Downloads a `wear-apk.zip` from [url] and extracts the contained `.apk`.
  Future<String> downloadZip(String url);

  /// Lets the user pick a local `.apk`; returns null when cancelled.
  Future<String?> pickLocal();
}

/// Extracts the APK from the zip bytes into [dir]. Entry names are never used as
/// paths (only the base name), so a malicious archive cannot write outside [dir].
Future<String> extractApkFromZip(List<int> zipBytes, Directory dir) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (e) {
    throw WatchInstallException(
      WatchInstallErrorType.downloadFailed,
      'Not a valid zip: $e',
    );
  }
  final apks = archive.files
      .where((f) => f.isFile && f.name.toLowerCase().endsWith('.apk'))
      .toList();
  if (apks.isEmpty) {
    throw WatchInstallException(
      WatchInstallErrorType.downloadFailed,
      'No .apk found in the archive',
    );
  }
  apks.sort((a, b) => a.name.length.compareTo(b.name.length));
  final entry = apks.first;
  final baseName = entry.name.split(RegExp(r'[\\/]')).last;
  final file = File('${dir.path}/$baseName');
  await file.writeAsBytes(entry.content);
  return file.path;
}

class DefaultApkFetcher implements ApkFetcher {
  DefaultApkFetcher([this._client]);
  final http.Client? _client;

  @override
  Future<String> downloadZip(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw WatchInstallException(
        WatchInstallErrorType.downloadFailed,
        'Invalid URL',
      );
    }
    final client = _client ?? http.Client();
    try {
      final response = await client.get(uri);
      if (response.statusCode != 200) {
        throw WatchInstallException(
          WatchInstallErrorType.downloadFailed,
          'HTTP ${response.statusCode}',
        );
      }
      final dir = await Directory.systemTemp.createTemp('wear-apk');
      return await extractApkFromZip(response.bodyBytes, dir);
    } on WatchInstallException {
      rethrow;
    } catch (e) {
      throw WatchInstallException(
        WatchInstallErrorType.downloadFailed,
        e.toString(),
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  @override
  Future<String?> pickLocal() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    final path = result.isEmpty ? null : result.first.path;
    if (path == null) return null;
    if (!path.toLowerCase().endsWith('.apk')) {
      throw WatchInstallException(
        WatchInstallErrorType.invalidApk,
        'Selected file is not an .apk',
      );
    }
    return path;
  }
}
