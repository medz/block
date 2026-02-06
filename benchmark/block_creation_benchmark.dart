import 'package:block/block.dart';

import 'framework.dart';

List<BenchmarkScenario> buildCreationScenarios() {
  final small = makeSequentialBytes(4 * 1024);
  final medium = makeSequentialBytes(1024 * 1024);
  final quarter = makeSequentialBytes(256 * 1024);
  final nestedPart = Block(<Object>[quarter]);

  return <BenchmarkScenario>[
    BenchmarkScenario.sync(
      name: 'create/single_part_4kb',
      category: 'Creation',
      iterations: 500,
      bytesPerIteration: small.length,
      maxIterationsPerProcess: 96,
      action: () {
        final block = Block(<Object>[small]);
        if (block.size != small.length) {
          throw StateError('size mismatch');
        }
      },
    ),
    BenchmarkScenario.sync(
      name: 'create/single_part_1mb',
      category: 'Creation',
      iterations: 80,
      bytesPerIteration: medium.length,
      maxIterationsPerProcess: 48,
      action: () {
        final block = Block(<Object>[medium]);
        if (block.size != medium.length) {
          throw StateError('size mismatch');
        }
      },
    ),
    BenchmarkScenario.sync(
      name: 'concat/bytes_4x256kb',
      category: 'Concatenation',
      iterations: 120,
      bytesPerIteration: 1024 * 1024,
      maxIterationsPerProcess: 64,
      action: () {
        final block = Block(<Object>[quarter, quarter, quarter, quarter]);
        if (block.size != 1024 * 1024) {
          throw StateError('size mismatch');
        }
      },
    ),
    BenchmarkScenario.sync(
      name: 'concat/blocks_4x256kb',
      category: 'Concatenation',
      iterations: 120,
      bytesPerIteration: 1024 * 1024,
      maxIterationsPerProcess: 64,
      action: () {
        final block = Block(<Object>[
          nestedPart,
          nestedPart,
          nestedPart,
          nestedPart,
        ]);
        if (block.size != 1024 * 1024) {
          throw StateError('size mismatch');
        }
      },
    ),
  ];
}
