import 'package:block/block.dart';

import 'framework.dart';

Future<List<BenchmarkResult>> runCreationBenchmarks() async {
  final small = makeSequentialBytes(4 * 1024);
  final medium = makeSequentialBytes(1 * 1024 * 1024);
  final large = makeSequentialBytes(8 * 1024 * 1024);

  final results = <BenchmarkResult>[
    measureSync(
      'create 4KB block',
      () {
        final block = Block(<Object>[small]);
        if (block.size != small.length) {
          throw StateError('size mismatch');
        }
      },
      iterations: 500,
      bytesPerIteration: small.length,
    ),
    measureSync(
      'create 1MB block',
      () {
        final block = Block(<Object>[medium]);
        if (block.size != medium.length) {
          throw StateError('size mismatch');
        }
      },
      iterations: 80,
      bytesPerIteration: medium.length,
    ),
    measureSync(
      'create 8MB block',
      () {
        final block = Block(<Object>[large]);
        if (block.size != large.length) {
          throw StateError('size mismatch');
        }
      },
      iterations: 15,
      bytesPerIteration: large.length,
    ),
    measureSync(
      'create multipart block (4x1MB)',
      () {
        final block = Block(<Object>[medium, medium, medium, medium]);
        if (block.size != medium.length * 4) {
          throw StateError('size mismatch');
        }
      },
      iterations: 40,
      bytesPerIteration: medium.length * 4,
    ),
  ];

  return results;
}
