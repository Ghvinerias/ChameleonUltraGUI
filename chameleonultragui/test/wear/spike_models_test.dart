import 'dart:async';
import 'dart:convert';

import 'package:chameleonultragui/wear/spike/spike_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('result JSON round trip', () {
    const r = SpikeResult(
        name: 'x',
        status: SpikeStatus.fail,
        details: 'boom',
        durationMs: 12,
        data: {'a': 1});
    final back = SpikeResult.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.name, 'x');
    expect(back.status, SpikeStatus.fail);
    expect(back.details, 'boom');
    expect(back.durationMs, 12);
    expect(back.data['a'], 1);
  });

  test('report round trip, replace by name and summary', () {
    final report = SpikeReport();
    report.notes['k'] = 'v';
    report.add(const SpikeResult(
        name: 'a', status: SpikeStatus.fail, details: '', durationMs: 1));
    report.add(const SpikeResult(
        name: 'a', status: SpikeStatus.ok, details: '', durationMs: 2));
    report.add(const SpikeResult(
        name: 'b', status: SpikeStatus.skipped, details: '', durationMs: 0));
    expect(report.results.length, 2);
    expect(report.summary(), startsWith('1 ok, 0 fail, 1 skipped'));
    final back = SpikeReport.fromJson(
        jsonDecode(report.toJsonString()) as Map<String, dynamic>);
    expect(back.results.length, 2);
    expect(back.notes['k'], 'v');
    expect(back.startedAt, report.startedAt);
  });

  test('runSpikeCheck catches exceptions and timeouts', () async {
    final thrown = await runSpikeCheck('t', () async => throw 'bad');
    expect(thrown.status, SpikeStatus.fail);
    expect(thrown.details, contains('bad'));

    final slow = await runSpikeCheck(
        's', () => Completer<SpikeOutcome>().future,
        timeout: const Duration(milliseconds: 20));
    expect(slow.status, SpikeStatus.fail);
    expect(slow.details, contains('timeout'));

    final ok = await runSpikeCheck(
        'o', () async => const SpikeOutcome.ok('fine', {'n': 1}));
    expect(ok.status, SpikeStatus.ok);
    expect(ok.data['n'], 1);
  });
}
