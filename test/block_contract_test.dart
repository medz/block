import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:test/test.dart';

void main() {
  group('Block contract', () {
    test('creates empty block', () {
      final block = Block(const <Object>[]);
      expect(block.size, equals(0));
      expect(block.type, equals(''));
    });

    test('concatenates supported parts in order', () async {
      final data = ByteData(2)
        ..setUint8(0, 65)
        ..setUint8(1, 66);
      final nested = Block(<Object>[
        Uint8List.fromList(const [67, 68]),
      ]);

      final block = Block(<Object>[
        'Hi',
        Uint8List.fromList(const [32]),
        data,
        nested,
      ]);

      expect(block.size, equals(7));
      expect(await block.text(), equals('Hi ABCD'));
    });

    test('supports custom type', () {
      final block = Block(<Object>[
        Uint8List.fromList(const [1, 2, 3]),
      ], type: 'application/octet-stream');
      expect(block.type, equals('application/octet-stream'));
    });

    test('arrayBuffer returns full bytes', () async {
      final block = Block(<Object>['hello']);
      final bytes = await block.arrayBuffer();
      expect(
        bytes,
        equals(Uint8List.fromList(const [104, 101, 108, 108, 111])),
      );
    });

    test('slice follows Blob-style index normalization', () async {
      final block = Block(<Object>['abcdef'], type: 'text/plain');

      final middle = block.slice(1, 4);
      final tail = block.slice(-2);
      final clamped = block.slice(-999, 9999);
      final empty = block.slice(4, 1);

      expect(await middle.text(), equals('bcd'));
      expect(await tail.text(), equals('ef'));
      expect(await clamped.text(), equals('abcdef'));
      expect(empty.size, equals(0));

      // Blob-compatible default slice type is empty string.
      expect(middle.type, equals(''));

      final customType = block.slice(0, 2, 'text/custom');
      expect(customType.type, equals('text/custom'));
    });

    test('stream yields full content respecting chunk size', () async {
      final bytes = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final block = Block(<Object>[bytes]);

      final streamed = <int>[];
      await for (final chunk in block.stream(chunkSize: 6)) {
        expect(chunk.length, lessThanOrEqualTo(6));
        streamed.addAll(chunk);
      }

      expect(streamed, equals(bytes));
    });

    test('supports nesting with Block parts', () async {
      final child = Block(<Object>['child']);
      final parent = Block(<Object>['[', child, ']']);
      expect(await parent.text(), equals('[child]'));
    });

    test('rejects unsupported part types', () {
      expect(() => Block(<Object>[1]), throwsArgumentError);
      expect(() => Block(<Object>[Object()]), throwsArgumentError);
    });

    test('rejects non-positive stream chunk size', () {
      final block = Block(<Object>['x']);
      expect(
        () async => block.stream(chunkSize: 0).drain<void>(),
        throwsArgumentError,
      );
      expect(
        () async => block.stream(chunkSize: -1).drain<void>(),
        throwsArgumentError,
      );
    });
  });
}
