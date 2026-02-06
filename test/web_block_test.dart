@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:block/src/testing/block_debug.dart';
import 'package:test/test.dart';

void main() {
  group('Web implementation', () {
    test('uses native web-backed implementation', () {
      final block = Block(<Object>['abc']);
      expect(blockImplementation(block), equals('web'));
    });

    test('arrayBuffer and text are consistent', () async {
      final block = Block(<Object>['hello web']);
      expect(await block.text(), equals('hello web'));

      final bytes = await block.arrayBuffer();
      expect(bytes, equals(Uint8List.fromList('hello web'.codeUnits)));
    });

    test('slice uses Blob-like semantics', () async {
      final block = Block(<Object>['abcdef'], type: 'text/plain');
      final slice = block.slice(2, -1);

      expect(await slice.text(), equals('cde'));
      expect(slice.type, equals(''));
    });

    test('stream bridges Blob.stream and enforces chunk size', () async {
      final source = Uint8List.fromList(List<int>.generate(50, (i) => i));
      final block = Block(<Object>[source]);

      final chunks = <Uint8List>[];
      await for (final chunk in block.stream(chunkSize: 7)) {
        expect(chunk.length, lessThanOrEqualTo(7));
        chunks.add(chunk);
      }

      final merged = Uint8List(source.length);
      var offset = 0;
      for (final chunk in chunks) {
        merged.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      expect(merged, equals(source));
    });
  });
}
