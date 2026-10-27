import 'dart:async';
import 'dart:convert';

enum SpikeStatus { ok, fail, skipped }

/// Outcome of one diagnostic check.
class SpikeResult {
  final String name;
  final SpikeStatus status;
  final String details;
  final int durationMs;

  /// Optional structured values (timings, counts) for the receiver.
  final Map<String, dynamic> data;

  const SpikeResult({
    required this.name,
    required this.status,
    required this.details,
    required this.durationMs,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status.name,
        'details': details,
        'durationMs': durationMs,
        'data': data,
      };

  factory SpikeResult.fromJson(Map<String, dynamic> json) => SpikeResult(
        name: json['name'] as String,
        status: SpikeStatus.values.byName(json['status'] as String),
        details: json['details'] as String? ?? '',
        durationMs: json['durationMs'] as int? ?? 0,
        data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      );
}

/// What a check body returns; [SpikeRunner.run] turns it into a [SpikeResult].
class SpikeOutcome {
  final SpikeStatus status;
  final String details;
  final Map<String, dynamic> data;

  const SpikeOutcome(this.status, this.details, [this.data = const {}]);
  const SpikeOutcome.ok(String details, [Map<String, dynamic> data = const {}])
      : this(SpikeStatus.ok, details, data);
  const SpikeOutcome.fail(String details,
      [Map<String, dynamic> data = const {}])
      : this(SpikeStatus.fail, details, data);
  const SpikeOutcome.skipped(String details)
      : this(SpikeStatus.skipped, details);
}

/// Runs a check body with a timeout; never throws.
Future<SpikeResult> runSpikeCheck(
  String name,
  Future<SpikeOutcome> Function() body, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final sw = Stopwatch()..start();
  try {
    final out = await body().timeout(timeout);
    return SpikeResult(
        name: name,
        status: out.status,
        details: out.details,
        durationMs: sw.elapsedMilliseconds,
        data: out.data);
  } on TimeoutException {
    return SpikeResult(
        name: name,
        status: SpikeStatus.fail,
        details: 'timeout after ${timeout.inSeconds} s',
        durationMs: sw.elapsedMilliseconds);
  } catch (e, st) {
    final stack = st.toString().split('\n').take(3).join(' | ');
    return SpikeResult(
        name: name,
        status: SpikeStatus.fail,
        details: '$e [$stack]',
        durationMs: sw.elapsedMilliseconds);
  }
}

/// All results of one spike session; later results replace earlier ones by name.
class SpikeReport {
  final DateTime startedAt;
  final Map<String, SpikeResult> _results = {};
  final Map<String, dynamic> notes = {};

  SpikeReport({DateTime? startedAt}) : startedAt = startedAt ?? DateTime.now();

  List<SpikeResult> get results => _results.values.toList();

  void add(SpikeResult r) => _results[r.name] = r;

  int count(SpikeStatus s) => _results.values.where((r) => r.status == s).length;

  /// Compact multi-line summary for the watch screen.
  String summary() {
    final b = StringBuffer(
        '${count(SpikeStatus.ok)} ok, ${count(SpikeStatus.fail)} fail, ${count(SpikeStatus.skipped)} skipped');
    for (final r in _results.values) {
      final mark = switch (r.status) {
        SpikeStatus.ok => 'OK',
        SpikeStatus.fail => 'FAIL',
        SpikeStatus.skipped => '--',
      };
      b.write('\n$mark ${r.name} (${r.durationMs} ms)');
    }
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'app': 'chameleon-wear-spike',
        'startedAt': startedAt.toIso8601String(),
        'generatedAt': DateTime.now().toIso8601String(),
        'notes': notes,
        'results': results.map((r) => r.toJson()).toList(),
      };

  String toJsonString() => const JsonEncoder.withIndent(' ').convert(toJson());

  factory SpikeReport.fromJson(Map<String, dynamic> json) {
    final report =
        SpikeReport(startedAt: DateTime.parse(json['startedAt'] as String));
    report.notes.addAll(Map<String, dynamic>.from(json['notes'] as Map? ?? {}));
    for (final r in json['results'] as List) {
      report.add(SpikeResult.fromJson(Map<String, dynamic>.from(r as Map)));
    }
    return report;
  }
}
