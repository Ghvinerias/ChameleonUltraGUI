import 'package:chameleonultragui/wear/spike/report_qr.dart';
import 'package:chameleonultragui/wear/spike/spike_screens.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:chameleonultragui/wear/spike/spike_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> sampleReport() {
    final r = SpikeReport();
    for (var i = 0; i < 8; i++) {
      r.add(SpikeResult(
          name: 'check_$i',
          status: i.isEven ? SpikeStatus.ok : SpikeStatus.fail,
          details: 'details ' * 40 + 'exception: boom [$i]',
          durationMs: 100 * i,
          data: {'n': i}));
    }
    r.notes['rotaryScrollEvents'] = 12;
    return r.toJson();
  }

  test('QR frames round-trip in any order', () {
    final report = sampleReport();
    final frames = encodeReportForQr(report);
    expect(frames.every((f) => f.startsWith('CWR1|')), isTrue);
    expect(frames.every((f) => f.length <= 330 + 28), isTrue);
    final expected = Map<String, dynamic>.of(report)..remove('generatedAt');
    expect(decodeReportFromQr(frames.reversed), expected);
  });

  test('small chunk size splits into more frames', () {
    final report = sampleReport();
    final many = encodeReportForQr(report, chunkChars: 60);
    expect(many.length, greaterThan(encodeReportForQr(report).length));
    expect(decodeReportFromQr(many),
        Map<String, dynamic>.of(report)..remove('generatedAt'));
  });

  test('reopening without new results gives identical frames', () {
    final base = sampleReport();
    final a = encodeReportForQr({...base, 'generatedAt': 'one'});
    final b = encodeReportForQr({...base, 'generatedAt': 'two'});
    expect(a, b);
  });

  test('frames from different snapshots are detected', () {
    final r1 = sampleReport();
    final r2 = Map<String, dynamic>.of(r1)..['notes'] = {'rotaryScrollEvents': 99};
    final f1 = encodeReportForQr(r1, chunkChars: 60);
    final f2 = encodeReportForQr(r2, chunkChars: 60);
    expect(
        () => decodeReportFromQr([f1.first, ...f2.skip(1)]),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('different reports'))));
  });

  test('a mis-scanned character fails the checksum', () {
    final frames = encodeReportForQr(sampleReport(), chunkChars: 60);
    final bits = frames[1].split('|');
    final data = bits[3];
    bits[3] = (data.startsWith('A') ? 'B' : 'A') + data.substring(1);
    expect(() => decodeReportFromQr([frames[0], bits.join('|'), ...frames.skip(2)]),
        throwsFormatException);
  });

  test('incomplete or foreign frames are rejected', () {
    final frames = encodeReportForQr(sampleReport(), chunkChars: 60);
    expect(() => decodeReportFromQr(frames.skip(1)), throwsFormatException);
    expect(() => decodeReportFromQr(['hello']), throwsFormatException);
  });

  testWidgets('QR page shows frames and steps through them', (tester) async {
    tester.view.physicalSize = const Size(438, 438);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final frames = encodeReportForQr(sampleReport());
    await tester.pumpWidget(MaterialApp(
        home: ReportQrPage(report: sampleReport())));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('QR 1 / ${frames.length}'), findsOneWidget);
    if (frames.length > 1) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      expect(find.textContaining('QR 2 / ${frames.length}'), findsOneWidget);
    }
  });
}
