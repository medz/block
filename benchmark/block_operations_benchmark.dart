import 'package:block/block.dart';

import 'framework.dart';

Future<List<BenchmarkResult>> runOperationBenchmarks() async {
  final baseBytes = makeSequentialBytes(8 * 1024 * 1024);
  final block = Block(<Object>[baseBytes], type: 'application/octet-stream');
  final textBlock = Block(<Object>[makeText(1024 * 1024)]);

  final results = <BenchmarkResult>[
    measureSync(
      'slice small (1KB, copy path)',
      () {
        final sliced = block.slice(0, 1024);
        if (sliced.size != 1024) {
          throw StateError('slice size mismatch');
        }
      },
      iterations: 500,
      bytesPerIteration: 1024,
    ),
    measureSync(
      'slice large (256KB, shared path)',
      () {
        final sliced = block.slice(64 * 1024, 320 * 1024);
        if (sliced.size != 256 * 1024) {
          throw StateError('slice size mismatch');
        }
      },
      iterations: 200,
      bytesPerIteration: 256 * 1024,
    ),
    await measureAsync(
      'arrayBuffer 8MB',
      () async {
        final bytes = await block.arrayBuffer();
        if (bytes.length != baseBytes.length) {
          throw StateError('arrayBuffer length mismatch');
        }
      },
      iterations: clampIterationsBySize(
        baseBytes.length,
        minIterations: 6,
        maxIterations: 24,
      ),
      bytesPerIteration: baseBytes.length,
    ),
    await measureAsync(
      'text decode 1MB',
      () async {
        final text = await textBlock.text();
        if (text.isEmpty) {
          throw StateError('text decode failed');
        }
      },
      iterations: 20,
      bytesPerIteration: 1024 * 1024,
    ),
    await measureAsync(
      'stream read 8MB (64KB chunks)',
      () async {
        var total = 0;
        await for (final chunk in block.stream(chunkSize: 64 * 1024)) {
          total += chunk.length;
        }
        if (total != baseBytes.length) {
          throw StateError('stream length mismatch');
        }
      },
      iterations: clampIterationsBySize(
        baseBytes.length,
        minIterations: 6,
        maxIterations: 20,
      ),
      bytesPerIteration: baseBytes.length,
    ),
  ];

  return results;
}
