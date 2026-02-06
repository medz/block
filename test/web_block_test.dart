@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'support/foreign_block.dart';

void main() {
  group('Web implementation', () {
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

    test('supports web.Blob and web.File parts', () async {
      final blobPart = web.Blob(
        <JSAny>[Uint8List.fromList('blob '.codeUnits).toJS].toJS,
      );
      final filePart = web.File(
        <JSAny>[Uint8List.fromList('file'.codeUnits).toJS].toJS,
        'demo.txt',
        web.FilePropertyBag(type: 'text/plain'),
      );

      final block = Block(<Object>[blobPart, filePart]);
      expect(await block.text(), equals('blob file'));
    });

    test('supports foreign Block implementations as parts', () async {
      final foreign = ForeignBlock.fromText('child');
      final block = Block(<Object>['[', foreign, ']']);

      expect(block.size, equals(7));
      expect(await block.text(), equals('[child]'));
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
