import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:block/src/testing/block_debug.dart';
import 'package:coal/coal.dart';

typedef BenchmarkCallback = Future<void> Function();

final class BenchmarkScenario {
  BenchmarkScenario({
    required this.name,
    required this.category,
    required this.iterations,
    required this.action,
    this.warmup = 2,
    this.bytesPerIteration,
    this.maxIterationsPerProcess,
  });

  factory BenchmarkScenario.sync({
    required String name,
    required String category,
    required int iterations,
    required void Function() action,
    int warmup = 2,
    int? bytesPerIteration,
    int? maxIterationsPerProcess,
  }) {
    return BenchmarkScenario(
      name: name,
      category: category,
      iterations: iterations,
      warmup: warmup,
      bytesPerIteration: bytesPerIteration,
      maxIterationsPerProcess: maxIterationsPerProcess,
      action: () async {
        action();
      },
    );
  }

  final String name;
  final String category;
  final int iterations;
  final int warmup;
  final int? bytesPerIteration;
  final int? maxIterationsPerProcess;
  final BenchmarkCallback action;
}

final class BenchmarkScenarioResult {
  BenchmarkScenarioResult({
    required this.name,
    required this.category,
    required this.iterations,
    required this.warmup,
    required this.totalUs,
    required this.avgUs,
    required this.p50Us,
    required this.p95Us,
    required this.p99Us,
    required this.tempFilesBefore,
    required this.tempFilesAfter,
    required this.tempFilesDelta,
    required this.rssBeforeBytes,
    required this.rssAfterBytes,
    required this.rssPeakBytes,
    this.samplesUs = const <double>[],
    this.bytesPerIteration,
  });

  final String name;
  final String category;
  final int iterations;
  final int warmup;
  final double totalUs;
  final double avgUs;
  final double p50Us;
  final double p95Us;
  final double p99Us;
  final int? bytesPerIteration;
  final int tempFilesBefore;
  final int tempFilesAfter;
  final int tempFilesDelta;
  final int rssBeforeBytes;
  final int rssAfterBytes;
  final int rssPeakBytes;
  final List<double> samplesUs;

  double? get throughputMBps {
    if (bytesPerIteration == null || totalUs <= 0) {
      return null;
    }
    final totalBytes = bytesPerIteration! * iterations;
    final seconds = totalUs / 1000000.0;
    return (totalBytes / (1024 * 1024)) / seconds;
  }

  double? get tempFilesPerIteration {
    if (iterations <= 0) {
      return null;
    }
    return tempFilesDelta / iterations;
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'category': category,
      'iterations': iterations,
      'warmup': warmup,
      'total_us': totalUs,
      'avg_us': avgUs,
      'p50_us': p50Us,
      'p95_us': p95Us,
      'p99_us': p99Us,
      'temp_files_before': tempFilesBefore,
      'temp_files_after': tempFilesAfter,
      'temp_files_delta': tempFilesDelta,
      'rss_before_bytes': rssBeforeBytes,
      'rss_after_bytes': rssAfterBytes,
      'rss_peak_bytes': rssPeakBytes,
      'samples_us': samplesUs,
      'bytes_per_iteration': bytesPerIteration,
    };
  }

  factory BenchmarkScenarioResult.fromJson(Map<String, Object?> json) {
    final rawSamples = json['samples_us'];
    final samples = <double>[];
    if (rawSamples is List<Object?>) {
      for (final sample in rawSamples) {
        if (sample is num) {
          samples.add(sample.toDouble());
        }
      }
    }

    return BenchmarkScenarioResult(
      name: _readString(json, 'name'),
      category: _readString(json, 'category'),
      iterations: _readInt(json, 'iterations'),
      warmup: _readInt(json, 'warmup'),
      totalUs: _readDouble(json, 'total_us'),
      avgUs: _readDouble(json, 'avg_us'),
      p50Us: _readDouble(json, 'p50_us'),
      p95Us: _readDouble(json, 'p95_us'),
      p99Us: _readDouble(json, 'p99_us'),
      tempFilesBefore: _readInt(json, 'temp_files_before'),
      tempFilesAfter: _readInt(json, 'temp_files_after'),
      tempFilesDelta: _readInt(json, 'temp_files_delta'),
      rssBeforeBytes: _readInt(json, 'rss_before_bytes'),
      rssAfterBytes: _readInt(json, 'rss_after_bytes'),
      rssPeakBytes: _readInt(json, 'rss_peak_bytes'),
      samplesUs: samples,
      bytesPerIteration: _readNullableInt(json, 'bytes_per_iteration'),
    );
  }
}

final class BenchmarkEnvironment {
  BenchmarkEnvironment({
    required this.os,
    required this.osVersion,
    required this.dartVersion,
    required this.cpuCount,
    required this.tempDirectory,
  });

  factory BenchmarkEnvironment.capture() {
    return BenchmarkEnvironment(
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      dartVersion: Platform.version,
      cpuCount: Platform.numberOfProcessors,
      tempDirectory: Directory.systemTemp.path,
    );
  }

  final String os;
  final String osVersion;
  final String dartVersion;
  final int cpuCount;
  final String tempDirectory;
}

final class BenchmarkRun {
  BenchmarkRun({
    required this.generatedAtUtc,
    required this.environment,
    required this.scenarios,
  });

  final DateTime generatedAtUtc;
  final BenchmarkEnvironment environment;
  final List<BenchmarkScenarioResult> scenarios;
}

Future<BenchmarkScenarioResult> runScenario(BenchmarkScenario scenario) async {
  final tempPrefix = ioBackingFilePrefix();
  final tempFilesBefore = _countTempFilesWithPrefix(tempPrefix);
  final rssBefore = _safeCurrentRss();
  var rssPeak = rssBefore;

  for (var i = 0; i < scenario.warmup; i++) {
    await scenario.action();
    final rssNow = _safeCurrentRss();
    if (rssNow > rssPeak) {
      rssPeak = rssNow;
    }
  }

  final iterationUs = <double>[];
  for (var i = 0; i < scenario.iterations; i++) {
    final watch = Stopwatch()..start();
    await scenario.action();
    watch.stop();
    iterationUs.add(watch.elapsedMicroseconds.toDouble());

    final rssNow = _safeCurrentRss();
    if (rssNow > rssPeak) {
      rssPeak = rssNow;
    }
  }

  final totalUs = iterationUs.fold<double>(0, (sum, current) => sum + current);
  final sortedLatencies = iterationUs.toList()..sort();
  final tempFilesAfter = _countTempFilesWithPrefix(tempPrefix);
  final rssAfter = _safeCurrentRss();

  return BenchmarkScenarioResult(
    name: scenario.name,
    category: scenario.category,
    iterations: scenario.iterations,
    warmup: scenario.warmup,
    totalUs: totalUs,
    avgUs: scenario.iterations == 0 ? 0 : totalUs / scenario.iterations,
    p50Us: _percentile(sortedLatencies, 0.50),
    p95Us: _percentile(sortedLatencies, 0.95),
    p99Us: _percentile(sortedLatencies, 0.99),
    bytesPerIteration: scenario.bytesPerIteration,
    tempFilesBefore: tempFilesBefore,
    tempFilesAfter: tempFilesAfter,
    tempFilesDelta: tempFilesAfter - tempFilesBefore,
    rssBeforeBytes: rssBefore,
    rssAfterBytes: rssAfter,
    rssPeakBytes: rssPeak,
    samplesUs: iterationUs,
  );
}

BenchmarkScenarioResult mergeScenarioChunks(
  BenchmarkScenario scenario,
  List<BenchmarkScenarioResult> chunks,
) {
  if (chunks.isEmpty) {
    throw ArgumentError.value(chunks, 'chunks', 'must not be empty');
  }

  final combinedSamples = <double>[];
  var iterations = 0;
  var warmup = 0;
  var totalUs = 0.0;
  var tempFilesDelta = 0;
  var rssPeak = chunks.first.rssPeakBytes;

  for (final chunk in chunks) {
    iterations += chunk.iterations;
    warmup += chunk.warmup;
    totalUs += chunk.totalUs;
    tempFilesDelta += chunk.tempFilesDelta;
    combinedSamples.addAll(chunk.samplesUs);
    if (chunk.rssPeakBytes > rssPeak) {
      rssPeak = chunk.rssPeakBytes;
    }
  }

  final sorted = combinedSamples.toList()..sort();
  final avgUs = iterations == 0 ? 0.0 : totalUs / iterations;

  return BenchmarkScenarioResult(
    name: scenario.name,
    category: scenario.category,
    iterations: iterations,
    warmup: warmup,
    totalUs: totalUs,
    avgUs: avgUs,
    p50Us: _percentile(sorted, 0.50),
    p95Us: _percentile(sorted, 0.95),
    p99Us: _percentile(sorted, 0.99),
    tempFilesBefore: chunks.first.tempFilesBefore,
    tempFilesAfter: chunks.last.tempFilesAfter,
    tempFilesDelta: tempFilesDelta,
    rssBeforeBytes: chunks.first.rssBeforeBytes,
    rssAfterBytes: chunks.last.rssAfterBytes,
    rssPeakBytes: rssPeak,
    samplesUs: combinedSamples,
    bytesPerIteration: scenario.bytesPerIteration,
  );
}

Future<BenchmarkRun> runBenchmarks(List<BenchmarkScenario> scenarios) async {
  final environment = BenchmarkEnvironment.capture();
  final results = <BenchmarkScenarioResult>[];

  for (final scenario in scenarios) {
    results.add(await runScenario(scenario));
  }

  return BenchmarkRun(
    generatedAtUtc: DateTime.now().toUtc(),
    environment: environment,
    scenarios: results,
  );
}

void printBenchmarkReport(BenchmarkRun run, {bool useColors = true}) {
  final colorsEnabled = useColors && stdout.supportsAnsiEscapes;
  String paint(String text, Iterable<TextStyle> styles) {
    if (!colorsEnabled) {
      return text;
    }
    return styleText(text, styles);
  }

  final timestamp = run.generatedAtUtc.toIso8601String();
  print(paint('Block benchmark run @ $timestamp', [TextStyle.bold]));
  print(
    '${paint('OS', [TextStyle.cyan])}: ${run.environment.os} ${run.environment.osVersion}',
  );
  print('${paint('Dart', [TextStyle.cyan])}: ${run.environment.dartVersion}');
  print('${paint('CPUs', [TextStyle.cyan])}: ${run.environment.cpuCount}');

  final byCategory = <String, List<BenchmarkScenarioResult>>{};
  for (final scenario in run.scenarios) {
    byCategory
        .putIfAbsent(scenario.category, () => <BenchmarkScenarioResult>[])
        .add(scenario);
  }

  for (final entry in byCategory.entries) {
    print(
      '\n${paint('=== ${entry.key} ===', [TextStyle.bold, TextStyle.green])}',
    );
    const headers = <String>[
      'scenario',
      'iters',
      'avg(us)',
      'p95(us)',
      'throughput(MB/s)',
      'temp/iter',
      'rss_peak(MB)',
    ];
    final rows = <List<String>>[];

    for (final scenario in entry.value) {
      final throughput = scenario.throughputMBps == null
          ? '-'
          : scenario.throughputMBps!.toStringAsFixed(2);
      final tempPerIteration = scenario.tempFilesPerIteration == null
          ? '-'
          : scenario.tempFilesPerIteration!.toStringAsFixed(4);
      final rssPeak = scenario.rssPeakBytes < 0
          ? '-'
          : (scenario.rssPeakBytes / (1024 * 1024)).toStringAsFixed(2);

      rows.add(<String>[
        scenario.name,
        '${scenario.iterations}',
        scenario.avgUs.toStringAsFixed(2),
        scenario.p95Us.toStringAsFixed(2),
        throughput,
        tempPerIteration,
        rssPeak,
      ]);
    }

    final widths = _computeColumnWidths(headers, rows);
    final divider = _tableDivider(widths);
    const rightAlignedColumns = <int>{1, 2, 3, 4, 5, 6};

    print(divider);
    print(_tableLine(headers, widths));
    print(divider);
    for (final row in rows) {
      print(_tableLine(row, widths, rightAlignedColumns: rightAlignedColumns));
    }
    print(divider);
  }
}

List<int> _computeColumnWidths(List<String> headers, List<List<String>> rows) {
  final widths = headers.map((header) => header.length).toList();
  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      if (row[i].length > widths[i]) {
        widths[i] = row[i].length;
      }
    }
  }
  return widths;
}

String _tableDivider(List<int> widths) {
  final segments = widths.map((width) => ''.padLeft(width, '-'));
  return '+-${segments.join('-+-')}-+';
}

String _tableLine(
  List<String> cells,
  List<int> widths, {
  Set<int> rightAlignedColumns = const <int>{},
}) {
  final formatted = <String>[];
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    final width = widths[i];
    final value = rightAlignedColumns.contains(i)
        ? cell.padLeft(width)
        : cell.padRight(width);
    formatted.add(value);
  }
  return '| ${formatted.join(' | ')} |';
}

Uint8List makeSequentialBytes(int size) {
  final data = Uint8List(size);
  for (var i = 0; i < size; i++) {
    data[i] = i & 0xFF;
  }
  return data;
}

String makeText(int size) {
  final chars = List<int>.generate(size, (i) => 65 + (i % 26));
  return String.fromCharCodes(chars);
}

int clampIterationsBySize(
  int bytes, {
  int minIterations = 5,
  int maxIterations = 1000,
}) {
  final rough = max(1, (16 * 1024 * 1024) ~/ max(1, bytes));
  return rough.clamp(minIterations, maxIterations);
}

double _percentile(List<double> sorted, double percentile) {
  if (sorted.isEmpty) {
    return 0;
  }
  final rank = percentile * (sorted.length - 1);
  final lowerIndex = rank.floor();
  final upperIndex = rank.ceil();
  if (lowerIndex == upperIndex) {
    return sorted[lowerIndex];
  }

  final lower = sorted[lowerIndex];
  final upper = sorted[upperIndex];
  final weight = rank - lowerIndex;
  return lower + (upper - lower) * weight;
}

int _safeCurrentRss() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return -1;
  }
}

int _countTempFilesWithPrefix(String prefix) {
  try {
    final entities = Directory.systemTemp.listSync(followLinks: false);
    var count = 0;
    for (final entity in entities) {
      final name = _basename(entity.path);
      if (name.startsWith(prefix)) {
        count++;
      }
    }
    return count;
  } catch (_) {
    return -1;
  }
}

String _basename(String path) {
  final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
  if (separatorIndex < 0 || separatorIndex == path.length - 1) {
    return path;
  }
  return path.substring(separatorIndex + 1);
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected "$key" to be String.');
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected "$key" to be int.');
}

double _readDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected "$key" to be double.');
}

int? _readNullableInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected "$key" to be int?.');
}
