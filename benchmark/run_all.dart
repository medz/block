import 'dart:io';

import 'block_creation_benchmark.dart';
import 'block_operations_benchmark.dart';
import 'deduplication_benchmark.dart';
import 'framework.dart';

void printHeader() {
  final now = DateTime.now().toIso8601String();
  print('Block benchmark run @ $now');
  print('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  print('Dart: ${Platform.version}');
  print('CPUs: ${Platform.numberOfProcessors}');
}

Future<void> main() async {
  printHeader();

  final creation = await runCreationBenchmarks();
  printResults('Creation', creation);

  final ops = await runOperationBenchmarks();
  printResults('Operations', ops);

  final composition = await runCompositionBenchmarks();
  printResults('Composition', composition);
}
