import 'dart:convert';
import 'dart:io';

/// Offline transport for the spike report: the watch shows the report as a few
/// QR codes, the user scans them with the phone camera and pastes the text.
///
/// Frame format (one QR each): `CWR1|<index>/<total>|<id>|<payload chunk>`.
/// The concatenated payload is `base64url(gzip(compact JSON))` without padding;
/// `<id>` is the FNV-1a hash of the full payload, so frames scanned from two
/// different snapshots of the report are detected instead of silently
/// producing a corrupt gzip stream.
const reportQrPrefix = 'CWR1';

/// Characters of payload per QR frame. Small enough to stay scannable on a
/// 438 px round screen (QR version about 15 at error level L).
const reportQrChunkChars = 330;

String _fnv1a32(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Encodes [report] as QR frame texts. Volatile fields (`generatedAt`) are
/// dropped so reopening the QR page without new results gives identical frames.
List<String> encodeReportForQr(Map<String, dynamic> report,
    {int chunkChars = reportQrChunkChars}) {
  final stable = Map<String, dynamic>.of(report)..remove('generatedAt');
  final packed = base64Url
      .encode(gzip.encode(utf8.encode(jsonEncode(stable))))
      .replaceAll('=', '');
  final id = _fnv1a32(packed);
  final total = (packed.length / chunkChars).ceil().clamp(1, 1 << 20);
  return [
    for (var i = 0; i < total; i++)
      '$reportQrPrefix|${i + 1}/$total|$id|'
          '${packed.substring(i * chunkChars, ((i + 1) * chunkChars).clamp(0, packed.length))}',
  ];
}

/// The id shared by all frames of one snapshot (as shown on the QR page).
String reportQrId(List<String> frames) => frames.first.split('|')[2];

/// Inverse of [encodeReportForQr]; frames may be in any order. Throws
/// [FormatException] if a frame is malformed, the set is incomplete, or frames
/// from different report snapshots are mixed.
Map<String, dynamic> decodeReportFromQr(Iterable<String> frames) {
  final parts = <int, String>{};
  int? total;
  String? id;
  for (final raw in frames) {
    final f = raw.trim();
    final bits = f.split('|');
    if (bits.length != 4 || bits[0] != reportQrPrefix) {
      throw FormatException('Not a report frame: $f');
    }
    final pos = bits[1].split('/');
    final i = int.parse(pos[0]);
    final n = int.parse(pos[1]);
    if ((total != null && total != n) || (id != null && id != bits[2])) {
      throw FormatException(
          'Frames come from different reports (ids $id and ${bits[2]}); '
          'rescan all codes in one session');
    }
    total = n;
    id = bits[2];
    parts[i] = bits[3];
  }
  if (total == null || parts.length != total) {
    throw FormatException(
        'Incomplete: have ${parts.length} of ${total ?? '?'} frames');
  }
  final packed = [for (var i = 1; i <= total; i++) parts[i]!].join();
  if (_fnv1a32(packed) != id) {
    throw const FormatException('Checksum mismatch: a frame was scanned wrongly');
  }
  final padded = packed + '=' * ((4 - packed.length % 4) % 4);
  final json = utf8.decode(gzip.decode(base64Url.decode(padded)));
  return Map<String, dynamic>.from(jsonDecode(json) as Map);
}
