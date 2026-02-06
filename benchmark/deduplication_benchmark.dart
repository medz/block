import 'package:block/block.dart';

import 'framework.dart';

Future<List<BenchmarkResult>> runCompositionBenchmarks() async {
  final oneMB = makeSequentialBytes(1024 * 1024);

  final nested = Block(<Object>[oneMB, oneMB]);

  final results = <BenchmarkResult>[
    measureSync(
      'compose from nested blocks (2MB)',
      () {
        final block = Block(<Object>[nested, nested]);
        if (block.size != 4 * 1024 * 1024) {
          throw StateError('compose size mismatch');
        }
      },
      iterations: 30,
      bytesPerIteration: 4 * 1024 * 1024,
    ),
    await measureAsync(
      'nested stream read (4MB, 128KB chunks)',
      () async {
        final block = Block(<Object>[nested, nested]);
        var total = 0;
        await for (final chunk in block.stream(chunkSize: 128 * 1024)) {
          total += chunk.length;
        }
        if (total != 4 * 1024 * 1024) {
          throw StateError('nested stream mismatch');
        }
      },
      iterations: 12,
      bytesPerIteration: 4 * 1024 * 1024,
    ),
  ];

  return results;
}
