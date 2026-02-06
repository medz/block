import 'dart:math';
import 'dart:typed_data';

final class BenchmarkResult {
  BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.totalUs,
    this.bytesPerIteration,
  });

  final String name;
  final int iterations;
  final double totalUs;
  final int? bytesPerIteration;

  double get avgUs => totalUs / iterations;

  double? get throughputMBps {
    if (bytesPerIteration == null || totalUs <= 0) {
      return null;
    }

    final totalBytes = bytesPerIteration! * iterations;
    final seconds = totalUs / 1000000.0;
    return (totalBytes / (1024 * 1024)) / seconds;
  }
}

Future<BenchmarkResult> measureAsync(
  String name,
  Future<void> Function() action, {
  required int iterations,
  int warmup = 2,
  int? bytesPerIteration,
}) async {
  for (var i = 0; i < warmup; i++) {
    await action();
  }

  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await action();
  }
  watch.stop();

  return BenchmarkResult(
    name: name,
    iterations: iterations,
    totalUs: watch.elapsedMicroseconds.toDouble(),
    bytesPerIteration: bytesPerIteration,
  );
}

BenchmarkResult measureSync(
  String name,
  void Function() action, {
  required int iterations,
  int warmup = 10,
  int? bytesPerIteration,
}) {
  for (var i = 0; i < warmup; i++) {
    action();
  }

  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    action();
  }
  watch.stop();

  return BenchmarkResult(
    name: name,
    iterations: iterations,
    totalUs: watch.elapsedMicroseconds.toDouble(),
    bytesPerIteration: bytesPerIteration,
  );
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

void printResults(String title, List<BenchmarkResult> results) {
  print('\n=== $title ===');
  print('| benchmark | iterations | total(ms) | avg(us) | throughput(MB/s) |');
  print('|---|---:|---:|---:|---:|');

  for (final result in results) {
    final totalMs = result.totalUs / 1000.0;
    final throughput = result.throughputMBps;
    final throughputText = throughput == null
        ? '-'
        : throughput.toStringAsFixed(2);

    print(
      '| ${result.name} | ${result.iterations} | ${totalMs.toStringAsFixed(2)} | ${result.avgUs.toStringAsFixed(2)} | $throughputText |',
    );
  }
}

int clampIterationsBySize(
  int bytes, {
  int minIterations = 5,
  int maxIterations = 1000,
}) {
  final rough = max(1, (16 * 1024 * 1024) ~/ max(1, bytes));
  return rough.clamp(minIterations, maxIterations);
}
