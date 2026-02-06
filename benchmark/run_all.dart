import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:coal/args.dart';

import 'block_creation_benchmark.dart';
import 'block_operations_benchmark.dart';
import 'composition_benchmark.dart';
import 'framework.dart';

Future<void> main(List<String> args) async {
  final parsed = Args.parse(
    args,
    bool: const ['help', 'no-color', 'worker'],
    string: const ['scenario', 'iterations', 'warmup'],
    aliases: const {'h': 'help'},
  );

  if ((parsed['help']?.safeAs<bool>()) ?? false) {
    print('Run block benchmarks in console.');
    print('');
    print('Usage:');
    print('  dart benchmark/run_all.dart [--no-color]');
    print('');
    print('Options:');
    print('  --no-color    Disable ANSI styling.');
    print('  -h, --help    Show this help.');
    return;
  }

  final scenarios = <BenchmarkScenario>[
    ...buildCreationScenarios(),
    ...buildOperationScenarios(),
    ...buildCompositionScenarios(),
  ];

  final scenarioMap = {
    for (final scenario in scenarios) scenario.name: scenario,
  };

  if ((parsed['worker']?.safeAs<bool>()) ?? false) {
    final scenarioName = parsed['scenario']?.safeAs<String>();
    if (scenarioName == null || !scenarioMap.containsKey(scenarioName)) {
      stderr.writeln('Unknown or missing --scenario for worker mode.');
      exitCode = 2;
      return;
    }

    final source = scenarioMap[scenarioName]!;
    final workerIterations = _parseIntArg(
      parsed['iterations']?.safeAs<String>(),
      fallback: source.iterations,
    );
    final workerWarmup = _parseIntArg(
      parsed['warmup']?.safeAs<String>(),
      fallback: source.warmup,
    );

    final workerScenario = BenchmarkScenario(
      name: source.name,
      category: source.category,
      iterations: workerIterations,
      warmup: workerWarmup,
      bytesPerIteration: source.bytesPerIteration,
      maxIterationsPerProcess: source.maxIterationsPerProcess,
      action: source.action,
    );

    final result = await runScenario(workerScenario);
    print('WORKER_RESULT_JSON=${jsonEncode(result.toJson())}');
    return;
  }

  final run = await _runBenchmarksWithWorkers(scenarios);

  printBenchmarkReport(
    run,
    useColors: !((parsed['no-color']?.safeAs<bool>()) ?? false),
  );
}

Future<BenchmarkRun> _runBenchmarksWithWorkers(
  List<BenchmarkScenario> scenarios,
) async {
  final environment = BenchmarkEnvironment.capture();
  final results = <BenchmarkScenarioResult>[];

  for (final scenario in scenarios) {
    final chunkSize = scenario.maxIterationsPerProcess;
    if (chunkSize == null || scenario.iterations <= chunkSize) {
      results.add(
        await _runWorkerChunk(
          scenario: scenario,
          iterations: scenario.iterations,
          warmup: scenario.warmup,
        ),
      );
      continue;
    }

    final chunks = <BenchmarkScenarioResult>[];
    var remaining = scenario.iterations;
    var first = true;

    while (remaining > 0) {
      final chunkIterations = min(chunkSize, remaining);
      chunks.add(
        await _runWorkerChunk(
          scenario: scenario,
          iterations: chunkIterations,
          warmup: first ? scenario.warmup : 0,
        ),
      );
      remaining -= chunkIterations;
      first = false;
    }

    results.add(mergeScenarioChunks(scenario, chunks));
  }

  return BenchmarkRun(
    generatedAtUtc: DateTime.now().toUtc(),
    environment: environment,
    scenarios: results,
  );
}

Future<BenchmarkScenarioResult> _runWorkerChunk({
  required BenchmarkScenario scenario,
  required int iterations,
  required int warmup,
}) async {
  final scriptPath = Platform.script.toFilePath();
  final workerArgs = <String>[
    'run',
    scriptPath,
    '--worker',
    '--scenario=${scenario.name}',
    '--iterations=$iterations',
    '--warmup=$warmup',
    '--no-color',
  ];

  final result = await Process.run(
    Platform.resolvedExecutable,
    workerArgs,
    workingDirectory: Directory.current.path,
  );

  if (result.exitCode != 0) {
    final stdoutText = '${result.stdout}'.trim();
    final stderrText = '${result.stderr}'.trim();
    throw StateError(
      'Benchmark worker failed for ${scenario.name} '
      '(exit ${result.exitCode}).\nSTDOUT:\n$stdoutText\nSTDERR:\n$stderrText',
    );
  }

  final stdoutText = '${result.stdout}';
  final marker = 'WORKER_RESULT_JSON=';
  final line = stdoutText
      .split('\n')
      .map((entry) => entry.trim())
      .firstWhere((entry) => entry.startsWith(marker), orElse: () => '');

  if (line.isEmpty) {
    throw StateError(
      'Benchmark worker did not return result for ${scenario.name}. '
      'STDOUT:\n$stdoutText',
    );
  }

  final payload = line.substring(marker.length);
  final decoded = jsonDecode(payload);
  if (decoded is Map<String, Object?>) {
    return BenchmarkScenarioResult.fromJson(decoded);
  }
  if (decoded is Map) {
    return BenchmarkScenarioResult.fromJson(decoded.cast<String, Object?>());
  }
  throw StateError('Unexpected worker payload for ${scenario.name}.');
}

int _parseIntArg(String? raw, {required int fallback}) {
  if (raw == null) {
    return fallback;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0) {
    return fallback;
  }
  return parsed;
}
