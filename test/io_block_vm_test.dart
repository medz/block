@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:block/io.dart';
import 'package:test/test.dart';

import 'support/foreign_block.dart';

void main() {
  group('IO implementation', () {
    test(
      'keeps small blocks in memory and materializes large blocks lazily',
      () async {
        await _withIsolatedSystemTemp((tempDir) async {
          expect(_countBlockTempFiles(tempDir), equals(0));

          final small = Block(<Object>[
            Uint8List.fromList(const [1, 2, 3]),
          ]);

          expect(_countBlockTempFiles(tempDir), equals(0));

          final smallBytes = await small.arrayBuffer();
          expect(smallBytes, equals(Uint8List.fromList(const [1, 2, 3])));
          expect(_countBlockTempFiles(tempDir), equals(0));

          final largeBytes = Uint8List.fromList(
            List<int>.generate(128 * 1024, (i) => i % 256),
          );
          final large = Block(<Object>[largeBytes]);

          expect(_countBlockTempFiles(tempDir), equals(0));

          final readBack = await large.arrayBuffer();
          expect(readBack, equals(largeBytes));
          expect(_countBlockTempFiles(tempDir), equals(1));
        });
      },
    );

    test('supports foreign Block parts lazily', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final child = ForeignBlock.fromText('child');
        final parent = Block(<Object>['[', child, ']']);

        expect(parent.size, equals(7));
        expect(_countBlockTempFiles(tempDir), equals(0));

        final slice = parent.slice(1, 6);
        expect(_countBlockTempFiles(tempDir), equals(0));

        expect(await slice.text(), equals('child'));
        expect(_countBlockTempFiles(tempDir), equals(1));

        expect(await parent.text(), equals('[child]'));
        expect(_countBlockTempFiles(tempDir), equals(2));
      });
    });

    test(
      'stream on large composed block does not materialize temp files',
      () async {
        await _withIsolatedSystemTemp((tempDir) async {
          final source = Uint8List.fromList(
            List<int>.generate(128 * 1024, (i) => i % 256),
          );
          final block = Block(<Object>[source]);

          expect(_countBlockTempFiles(tempDir), equals(0));

          final streamed = <int>[];
          await for (final chunk in block.stream(chunkSize: 2 * 1024)) {
            expect(chunk.length, lessThanOrEqualTo(2 * 1024));
            streamed.addAll(chunk);
          }

          expect(streamed, equals(source));
          expect(_countBlockTempFiles(tempDir), equals(0));

          expect(await block.arrayBuffer(), equals(source));
          expect(_countBlockTempFiles(tempDir), equals(1));
        });
      },
    );

    test('slice <= 64KB copies into a new temp file', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final data = Uint8List.fromList(
          List<int>.generate(200 * 1024, (i) => i % 256),
        );
        final parent = Block(<Object>[data]);
        final child = parent.slice(1024, 1024 + 1024);

        expect(_countBlockTempFiles(tempDir), equals(0));

        final bytes = await child.arrayBuffer();
        expect(bytes, equals(data.sublist(1024, 2048)));
        expect(_countBlockTempFiles(tempDir), equals(1));

        await parent.arrayBuffer();
        expect(_countBlockTempFiles(tempDir), equals(2));
      });
    });

    test('slice > 64KB shares parent materialized file', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final data = Uint8List.fromList(
          List<int>.generate(300 * 1024, (i) => i % 256),
        );
        final parent = Block(<Object>[data]);
        final child = parent.slice(4096, 4096 + 128 * 1024);

        expect(_countBlockTempFiles(tempDir), equals(0));

        final bytes = await child.arrayBuffer();
        expect(bytes, equals(data.sublist(4096, 4096 + 128 * 1024)));
        expect(_countBlockTempFiles(tempDir), equals(1));

        await parent.arrayBuffer();
        expect(_countBlockTempFiles(tempDir), equals(1));
      });
    });

    test(
      'FileBlock.open reads source files without temp materialization',
      () async {
        await _withIsolatedSystemTemp((tempDir) async {
          final data = Uint8List.fromList(
            List<int>.generate(128 * 1024, (i) => i % 256),
          );
          final file = File(
            '${tempDir.path}${Platform.pathSeparator}source_open.bin',
          );
          await file.writeAsBytes(data);

          final block = await FileBlock.open(
            file,
            type: 'application/octet-stream',
          );

          expect(block.size, equals(data.length));
          expect(block.type, equals('application/octet-stream'));
          expect(_countBlockTempFiles(tempDir), equals(0));

          final readBack = await block.arrayBuffer();
          expect(readBack, equals(data));
          expect(_countBlockTempFiles(tempDir), equals(0));
          expect(await file.exists(), isTrue);
        });
      },
    );

    test('FileBlock range and slice stay on the source file', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final data = Uint8List.fromList(
          List<int>.generate(128 * 1024, (i) => i % 256),
        );
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}source_range.bin',
        );
        await file.writeAsBytes(data);

        final block = await FileBlock.openRange(
          file,
          offset: 1024,
          length: 4096,
          type: 'application/octet-stream',
        );
        final slice = block.slice(256, 1280);

        expect(slice, isA<FileBlock>());
        expect(await slice.arrayBuffer(), equals(data.sublist(1280, 2304)));
        expect(_countBlockTempFiles(tempDir), equals(0));
        expect(await file.exists(), isTrue);
      });
    });

    test('FileBlock.openRange rejects invalid ranges', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final data = Uint8List.fromList(
          List<int>.generate(1024, (i) => i % 256),
        );
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}source_invalid_range.bin',
        );
        await file.writeAsBytes(data);

        await expectLater(
          () => FileBlock.openRange(file, offset: -1, length: 1),
          throwsA(isA<RangeError>()),
        );
        await expectLater(
          () => FileBlock.openRange(file, offset: data.length + 1, length: 1),
          throwsA(isA<RangeError>()),
        );
        await expectLater(
          () => FileBlock.openRange(file, offset: data.length - 1, length: 2),
          throwsA(isA<RangeError>()),
        );

        expect(_countBlockTempFiles(tempDir), equals(0));
        expect(await file.exists(), isTrue);
      });
    });

    test('FileBlock composes lazily with Block parts', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final data = Uint8List.fromList(
          List<int>.generate(96 * 1024, (i) => i % 256),
        );
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}source_composed.bin',
        );
        await file.writeAsBytes(data);

        final fileBlock = await FileBlock.open(file);
        final block = Block(<Object>[fileBlock, '!']);

        expect(_countBlockTempFiles(tempDir), equals(0));

        final streamed = <int>[];
        await for (final chunk in block.stream(chunkSize: 8 * 1024)) {
          streamed.addAll(chunk);
        }

        expect(streamed, equals(<int>[...data, '!'.codeUnitAt(0)]));
        expect(_countBlockTempFiles(tempDir), equals(0));
        expect(await file.exists(), isTrue);
      });
    });

    test('Block constructor accepts File parts lazily on IO', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final data = Uint8List.fromList(
          List<int>.generate(96 * 1024, (i) => i % 256),
        );
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}source_direct_file.bin',
        );
        await file.writeAsBytes(data);

        final block = Block(<Object>['[', file, ']']);

        expect(block.size, equals(data.length + 2));
        expect(_countBlockTempFiles(tempDir), equals(0));

        final streamed = <int>[];
        await for (final chunk in block.stream(chunkSize: 8 * 1024)) {
          streamed.addAll(chunk);
        }

        expect(
          streamed,
          equals(<int>['['.codeUnitAt(0), ...data, ']'.codeUnitAt(0)]),
        );
        expect(_countBlockTempFiles(tempDir), equals(0));
        expect(await file.exists(), isTrue);
      });
    });

    test(
      'Block constructor does not open File parts until first read',
      () async {
        if (!_canInspectOpenFiles()) {
          return;
        }

        await _withIsolatedSystemTemp((tempDir) async {
          final data = Uint8List.fromList(
            List<int>.generate(4 * 1024, (i) => i % 256),
          );
          final file = File(
            '${tempDir.path}${Platform.pathSeparator}source_lazy_fd.bin',
          );
          await file.writeAsBytes(data);

          final baseline = await _countOpenDescriptorsFor(file);
          final block = Block(<Object>[file]);

          expect(block.size, equals(data.length));
          expect(await _countOpenDescriptorsFor(file), equals(baseline));

          await block.arrayBuffer();
          expect(await _countOpenDescriptorsFor(file), greaterThanOrEqualTo(1));
        });
      },
    );
  });
}

Future<void> _withIsolatedSystemTemp(
  Future<void> Function(Directory tempDir) body,
) async {
  final tempRoot = await Directory.systemTemp.createTemp('block_test_io_');

  try {
    await IOOverrides.runZoned(() async {
      await body(tempRoot);
    }, getSystemTempDirectory: () => tempRoot);
  } finally {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  }
}

int _countBlockTempFiles(Directory tempDir) {
  const prefix = 'block_io_';
  final entities = tempDir.listSync(followLinks: false);
  var count = 0;

  for (final entity in entities) {
    if (entity is! File) {
      continue;
    }

    final name = _basename(entity.path);
    if (name.startsWith(prefix)) {
      count++;
    }
  }

  return count;
}

String _basename(String path) {
  final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
  if (separatorIndex < 0 || separatorIndex == path.length - 1) {
    return path;
  }
  return path.substring(separatorIndex + 1);
}

bool _canInspectOpenFiles() {
  try {
    final result = Process.runSync('which', const ['lsof']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<int> _countOpenDescriptorsFor(File file) async {
  final resolvedPath = await file.resolveSymbolicLinks();
  final result = await Process.run('lsof', ['-p', '$pid']);
  if (result.exitCode != 0) {
    throw StateError('Failed to inspect open files: ${result.stderr}');
  }

  final output = '${result.stdout}';
  return output.split('\n').where((line) => line.contains(resolvedPath)).length;
}
