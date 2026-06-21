import 'package:block/block.dart';

import 'framework.dart';

List<BenchmarkScenario> buildCompositionScenarios() {
  final oneMB = makeSequentialBytes(1024 * 1024);
  final nested = Block(<Object>[oneMB, oneMB]);
  final manySmallParts = List<Object>.generate(
    1024,
    (_) => makeSequentialBytes(4 * 1024),
    growable: false,
  );
  final manyPartBlock = Block(manySmallParts);
  final random4kbOffsets = List<int>.generate(
    96,
    (i) => ((i * 37) % 1024) * 4 * 1024,
    growable: false,
  );
  final random64kbOffsets = List<int>.generate(
    48,
    (i) => ((i * 29) % (1024 - 16)) * 4 * 1024,
    growable: false,
  );
  var random4kbIndex = 0;
  var random64kbIndex = 0;

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
    BenchmarkScenario.sync(
      name: 'compose/many_parts_1024x4kb',
      category: 'Composition',
      iterations: 80,
      bytesPerIteration: 4 * 1024 * 1024,
      maxIterationsPerProcess: 40,
      action: () {
        final block = Block(manySmallParts);
        if (block.size != 4 * 1024 * 1024) {
          throw StateError('many-part compose size mismatch');
        }
      },
    ),
    BenchmarkScenario(
      name: 'range/many_parts_random_slice_4kb',
      category: 'Range',
      iterations: 96,
      bytesPerIteration: 4 * 1024,
      // Keep the deterministic offset sequence in one worker process.
      action: () async {
        final offset =
            random4kbOffsets[random4kbIndex++ % random4kbOffsets.length];
        final bytes = await manyPartBlock
            .slice(offset, offset + 4 * 1024)
            .arrayBuffer();
        if (bytes.length != 4 * 1024 || bytes.first != 0 || bytes.last != 255) {
          throw StateError('many-part 4KB range mismatch');
        }
      },
    ),
    BenchmarkScenario(
      name: 'range/many_parts_random_slice_64kb',
      category: 'Range',
      iterations: 48,
      bytesPerIteration: 64 * 1024,
      action: () async {
        final offset =
            random64kbOffsets[random64kbIndex++ % random64kbOffsets.length];
        final bytes = await manyPartBlock
            .slice(offset, offset + 64 * 1024)
            .arrayBuffer();
        if (bytes.length != 64 * 1024 ||
            bytes.first != 0 ||
            bytes.last != 255) {
          throw StateError('many-part 64KB range mismatch');
        }
      },
    ),
    BenchmarkScenario(
      name: 'stream/many_parts_4mb_chunk64kb',
      category: 'Stream',
      iterations: 12,
      bytesPerIteration: 4 * 1024 * 1024,
      maxIterationsPerProcess: 12,
      action: () async {
        var total = 0;
        await for (final chunk in manyPartBlock.stream(chunkSize: 64 * 1024)) {
          total += chunk.length;
        }
        if (total != 4 * 1024 * 1024) {
          throw StateError('many-part stream mismatch');
        }
      },
    ),
  ];
}
