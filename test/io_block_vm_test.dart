@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:test/test.dart';

import 'support/foreign_block.dart';

void main() {
  group('IO implementation', () {
    test('materializes temporary file on first read', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        expect(_countBlockTempFiles(tempDir), equals(0));

        final block = Block(<Object>[
          Uint8List.fromList(const [1, 2, 3]),
        ]);

        expect(_countBlockTempFiles(tempDir), equals(0));

        final bytes = await block.arrayBuffer();
        expect(bytes, equals(Uint8List.fromList(const [1, 2, 3])));
        expect(_countBlockTempFiles(tempDir), equals(1));
      });
    });

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

    test('stream on composed block does not materialize temp files', () async {
      await _withIsolatedSystemTemp((tempDir) async {
        final child = Block(<Object>['child']);
        final parent = Block(<Object>['[', child, ']']);

        expect(_countBlockTempFiles(tempDir), equals(0));

        final streamed = <int>[];
        await for (final chunk in parent.stream(chunkSize: 2)) {
          expect(chunk.length, lessThanOrEqualTo(2));
          streamed.addAll(chunk);
        }

        expect(streamed, equals(Uint8List.fromList('[child]'.codeUnits)));
        expect(_countBlockTempFiles(tempDir), equals(0));

        expect(
          await parent.arrayBuffer(),
          equals(Uint8List.fromList('[child]'.codeUnits)),
        );
        expect(_countBlockTempFiles(tempDir), equals(1));
      });
    });

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
