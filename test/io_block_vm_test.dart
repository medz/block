@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:block/src/testing/block_debug.dart';
import 'package:test/test.dart';

void main() {
  group('IO implementation', () {
    test('materializes temporary file backing on first read', () async {
      final block = Block(<Object>[
        Uint8List.fromList(const [1, 2, 3]),
      ]);

      expect(blockImplementation(block), equals('io'));

      expect(ioBackingPath(block), isNull);
      expect(ioBackingIdentity(block), isNull);

      final bytes = await block.arrayBuffer();
      expect(bytes, equals(Uint8List.fromList(const [1, 2, 3])));

      final path = ioBackingPath(block);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);

      final name = path.split(Platform.pathSeparator).last;
      expect(name, startsWith(ioBackingFilePrefix()));
    });

    test('nested Block parts are materialized lazily on first read', () async {
      final child = Block(<Object>['child']);
      final parent = Block(<Object>['[', child, ']']);

      expect(parent.size, equals(7));
      expect(ioBackingPath(parent), isNull);
      expect(ioBackingIdentity(parent), isNull);

      final slice = parent.slice(1, 6);
      expect(ioBackingPath(slice), isNull);
      expect(ioBackingIdentity(slice), isNull);

      expect(await parent.text(), equals('[child]'));
      expect(ioBackingPath(parent), isNotNull);
      expect(ioBackingIdentity(parent), isNotNull);

      expect(await slice.text(), equals('child'));
      expect(ioBackingPath(slice), isNotNull);
      expect(ioBackingIdentity(slice), isNotNull);
    });

    test('slice <= 64KB copies into a new backing file', () async {
      final data = Uint8List.fromList(
        List<int>.generate(200 * 1024, (i) => i % 256),
      );
      final parent = Block(<Object>[data]);
      final child = parent.slice(1024, 1024 + 1024);

      expect(ioBackingIdentity(parent), isNull);
      expect(ioBackingIdentity(child), isNull);

      final bytes = await child.arrayBuffer();
      expect(bytes, equals(data.sublist(1024, 2048)));

      expect(ioBackingIdentity(child), isNotNull);
      expect(ioBackingIdentity(parent), isNull);

      await parent.arrayBuffer();
      expect(ioBackingIdentity(parent), isNotNull);
      expect(
        ioBackingIdentity(child),
        isNot(equals(ioBackingIdentity(parent))),
      );
    });

    test('slice > 64KB shares parent backing file', () async {
      final data = Uint8List.fromList(
        List<int>.generate(300 * 1024, (i) => i % 256),
      );
      final parent = Block(<Object>[data]);
      final child = parent.slice(4096, 4096 + 128 * 1024);

      expect(ioBackingIdentity(parent), isNull);
      expect(ioBackingIdentity(child), isNull);

      final bytes = await child.arrayBuffer();
      expect(bytes, equals(data.sublist(4096, 4096 + 128 * 1024)));

      final parentBacking = ioBackingIdentity(parent);
      expect(parentBacking, isNotNull);
      expect(ioBackingIdentity(child), equals(parentBacking));
    });
  });
}
