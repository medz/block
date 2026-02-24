import 'dart:io';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('io backend uses temp file and slice threshold strategy', (
    tester,
  ) async {
    await _withIsolatedSystemTemp((tempDir) async {
      final source = Uint8List.fromList(
        List<int>.generate(300 * 1024, (i) => i % 256),
      );

      final block = Block(<Object>[source], type: 'application/octet-stream');
      expect(_countBlockTempFiles(tempDir), equals(0));

      final streamed = <int>[];
      await for (final chunk in block.stream(chunkSize: 64 * 1024)) {
        expect(chunk.length, lessThanOrEqualTo(64 * 1024));
        streamed.addAll(chunk);
      }
      expect(streamed, equals(source));
      expect(_countBlockTempFiles(tempDir), equals(0));

      final smallSlice = block.slice(0, 1024);
      final largeSlice = block.slice(0, 128 * 1024);
      expect(_countBlockTempFiles(tempDir), equals(0));

      final smallBytes = await smallSlice.arrayBuffer();
      expect(smallBytes, equals(source.sublist(0, 1024)));
      expect(_countBlockTempFiles(tempDir), equals(1));

      final largeBytes = await largeSlice.arrayBuffer();
      expect(largeBytes, equals(source.sublist(0, 128 * 1024)));
      expect(_countBlockTempFiles(tempDir), equals(2));

      final parentBytes = await block.arrayBuffer();
      expect(parentBytes, equals(source));
      expect(_countBlockTempFiles(tempDir), equals(2));

      final textBlock = Block(<Object>['abc']);
      expect(_countBlockTempFiles(tempDir), equals(2));
      expect(await textBlock.text(), equals('abc'));
      expect(_countBlockTempFiles(tempDir), equals(2));
    });
  });
}

Future<void> _withIsolatedSystemTemp(
  Future<void> Function(Directory tempDir) body,
) async {
  final tempRoot = await Directory.systemTemp.createTemp('block_it_io_');

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
