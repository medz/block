@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:block/src/testing/block_debug.dart';
import 'package:test/test.dart';

void main() {
  group('IO implementation', () {
    test('uses temporary file backing', () {
      final block = Block(<Object>[
        Uint8List.fromList(const [1, 2, 3]),
      ]);

      expect(blockImplementation(block), equals('io'));

      final path = ioBackingPath(block);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);

      final name = path.split(Platform.pathSeparator).last;
      expect(name, startsWith(ioBackingFilePrefix()));
    });

    test('slice <= 64KB copies into a new backing file', () async {
      final data = Uint8List.fromList(
        List<int>.generate(200 * 1024, (i) => i % 256),
      );
      final parent = Block(<Object>[data]);
      final child = parent.slice(1024, 1024 + 1024);

      expect(
        ioBackingIdentity(child),
        isNot(equals(ioBackingIdentity(parent))),
      );

      final bytes = await child.arrayBuffer();
      expect(bytes, equals(data.sublist(1024, 2048)));
    });

    test('slice > 64KB shares parent backing file', () async {
      final data = Uint8List.fromList(
        List<int>.generate(300 * 1024, (i) => i % 256),
      );
      final parent = Block(<Object>[data]);
      final child = parent.slice(4096, 4096 + 128 * 1024);

      expect(ioBackingIdentity(child), equals(ioBackingIdentity(parent)));

      final bytes = await child.arrayBuffer();
      expect(bytes, equals(data.sublist(4096, 4096 + 128 * 1024)));
    });
  });
}
