import 'package:block/block.dart';

import 'framework.dart';

List<BenchmarkScenario> buildCompositionScenarios() {
  final oneMB = makeSequentialBytes(1024 * 1024);
  final nested = Block(<Object>[oneMB, oneMB]);

  return <BenchmarkScenario>[
    BenchmarkScenario.sync(
      name: 'compose/from_nested_blocks_4mb',
      category: 'Composition',
      iterations: 30,
      bytesPerIteration: 4 * 1024 * 1024,
      maxIterationsPerProcess: 24,
      action: () {
        final block = Block(<Object>[nested, nested]);
        if (block.size != 4 * 1024 * 1024) {
          throw StateError('compose size mismatch');
        }
      },
    ),
    BenchmarkScenario(
      name: 'stream/nested_read_4mb_chunk128kb',
      category: 'Composition',
      iterations: 12,
      bytesPerIteration: 4 * 1024 * 1024,
      maxIterationsPerProcess: 12,
      action: () async {
        final block = Block(<Object>[nested, nested]);
        var total = 0;
        await for (final chunk in block.stream(chunkSize: 128 * 1024)) {
          total += chunk.length;
        }
        if (total != 4 * 1024 * 1024) {
          throw StateError('nested stream mismatch');
        }
      },
    ),
  ];
}
