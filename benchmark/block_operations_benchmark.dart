import 'package:block/block.dart';

import 'framework.dart';

List<BenchmarkScenario> buildOperationScenarios() {
  final baseBytes = makeSequentialBytes(8 * 1024 * 1024);
  final block = Block(<Object>[baseBytes], type: 'application/octet-stream');
  final textBlock = Block(<Object>[makeText(1024 * 1024)]);

  return <BenchmarkScenario>[
    BenchmarkScenario.sync(
      name: 'slice/copy_64kb',
      category: 'Slice',
      iterations: 400,
      bytesPerIteration: 64 * 1024,
      maxIterationsPerProcess: 96,
      action: () {
        final sliced = block.slice(0, 64 * 1024);
        if (sliced.size != 64 * 1024) {
          throw StateError('slice size mismatch');
        }
      },
    ),
    BenchmarkScenario.sync(
      name: 'slice/share_256kb',
      category: 'Slice',
      iterations: 200,
      action: () {
        final sliced = block.slice(64 * 1024, 320 * 1024);
        if (sliced.size != 256 * 1024) {
          throw StateError('slice size mismatch');
        }
      },
    ),
    BenchmarkScenario(
      name: 'read/array_buffer_8mb',
      category: 'Read',
      iterations: clampIterationsBySize(
        baseBytes.length,
        minIterations: 6,
        maxIterations: 24,
      ),
      bytesPerIteration: baseBytes.length,
      action: () async {
        final bytes = await block.arrayBuffer();
        if (bytes.length != baseBytes.length) {
          throw StateError('arrayBuffer length mismatch');
        }
      },
    ),
    BenchmarkScenario(
      name: 'read/text_decode_1mb',
      category: 'Read',
      iterations: 20,
      bytesPerIteration: 1024 * 1024,
      action: () async {
        final text = await textBlock.text();
        if (text.isEmpty) {
          throw StateError('text decode failed');
        }
      },
    ),
    BenchmarkScenario(
      name: 'stream/read_8mb_chunk64kb',
      category: 'Stream',
      iterations: clampIterationsBySize(
        baseBytes.length,
        minIterations: 6,
        maxIterations: 20,
      ),
      bytesPerIteration: baseBytes.length,
      action: () async {
        var total = 0;
        await for (final chunk in block.stream(chunkSize: 64 * 1024)) {
          total += chunk.length;
        }
        if (total != baseBytes.length) {
          throw StateError('stream length mismatch');
        }
      },
    ),
  ];
}
