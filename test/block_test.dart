import 'dart:convert';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:test/test.dart';

void main() {
  group('Block constructor tests', () {
    test('Basic constructor', () {
      final block = Block((add) {
        add(Uint8List.fromList([1, 2, 3]));
        add(Uint8List.fromList([4, 5]));
      });

      expect(block.size, equals(5));
    });

    test('Empty block constructor', () {
      final block = Block.empty();
      expect(block.size, equals(0));
    });

    test('From string constructor', () {
      final block = Block.fromString(['Hello', ' ', 'World']);
      expect(block.size, equals(11)); // 'Hello World'.length
    });

    test('From bytes constructor', () {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6, 7]);
      final block = Block.fromBytes([bytes1, bytes2]);

      expect(block.size, equals(7));
    });
  });

  group('Block.stream() tests', () {
    test('Correctly returns data chunks', () async {
      final block = Block((add) {
        add(Uint8List.fromList([1, 2, 3]));
        add(Uint8List.fromList([4, 5]));
      });

      final chunks = await block.stream().toList();
      expect(chunks.length, equals(2));
      expect(chunks[0], equals([1, 2, 3]));
      expect(chunks[1], equals([4, 5]));
    });

    test('Multiple calls should return same data', () async {
      final block = Block((add) {
        add(Uint8List.fromList([1, 2, 3]));
        add(Uint8List.fromList([4, 5]));
      });

      final chunks1 = await block.stream().toList();
      final chunks2 = await block.stream().toList();

      expect(chunks1, equals(chunks2));
    });

    test('Empty block should return empty stream', () async {
      final block = Block.empty();
      final chunks = await block.stream().toList();
      expect(chunks, isEmpty);
    });
  });

  group('Block.bytes() tests', () {
    test('Correctly merges all bytes', () async {
      final block = Block((add) {
        add(Uint8List.fromList([1, 2, 3]));
        add(Uint8List.fromList([4, 5]));
      });

      final bytes = await block.bytes();
      expect(bytes, equals([1, 2, 3, 4, 5]));
    });

    test('Multiple calls should return the same result', () async {
      final block = Block((add) {
        add(Uint8List.fromList([1, 2, 3]));
        add(Uint8List.fromList([4, 5]));
      });

      final bytes1 = await block.bytes();
      final bytes2 = await block.bytes();

      // Should be the same data
      expect(bytes1, equals(bytes2));

      // Should be the same object reference (cache check)
      expect(identical(bytes1, bytes2), isTrue);
    });

    test('Empty block should return empty byte array', () async {
      final block = Block.empty();
      final bytes = await block.bytes();
      expect(bytes, isEmpty);
      expect(bytes.length, equals(0));
    });

    test('Large block handling (>10MB)', () async {
      // Create a block larger than 10MB
      final largeChunk = Uint8List(8 * 1024 * 1024); // 8MB
      for (int i = 0; i < largeChunk.length; i++) {
        largeChunk[i] = i % 256;
      }

      final block = Block((add) {
        add(largeChunk);
        add(largeChunk); // Total 16MB
      });

      expect(block.size, equals(16 * 1024 * 1024));

      final bytes = await block.bytes();
      expect(bytes.length, equals(16 * 1024 * 1024));

      // Verify some sample bytes
      expect(bytes[0], equals(0));
      expect(bytes[1000000], equals(1000000 % 256));
      expect(bytes[8 * 1024 * 1024], equals(0)); // Start of second chunk
    });
  });

  group('Block.text() tests', () {
    test('Correctly decodes UTF-8 text', () async {
      final block = Block((add) {
        add(utf8.encode('Hello'));
        add(utf8.encode(' World'));
      });

      final text = await block.text();
      expect(text, equals('Hello World'));
    });

    test('Multiple calls should return the same result', () async {
      final block = Block.fromString(['Hello World']);

      final text1 = await block.text();
      final text2 = await block.text();

      expect(text1, equals(text2));
      expect(identical(text1, text2), isTrue); // Cache test
    });

    test('Handles invalid UTF-8', () async {
      // Create invalid UTF-8 sequence
      final invalidUtf8 = Uint8List.fromList([0xFF, 0xFE, 0xFD]);

      final block = Block((add) {
        add(invalidUtf8);
      });

      // Should use lenient decoding instead of throwing
      final text = await block.text();
      expect(text, isNotEmpty); // Exact output depends on implementation
    });

    test('Empty block should return empty string', () async {
      final block = Block.empty();
      final text = await block.text();
      expect(text, isEmpty);
    });
  });

  group('Block.slice() tests', () {
    test('Basic slice operation', () async {
      final block = Block((add) {
        add(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
      });

      final slice = block.slice(2, 7); // [3,4,5,6,7]

      expect(slice.size, equals(5));
      final bytes = await slice.bytes();
      expect(bytes, equals([3, 4, 5, 6, 7]));
    });

    test('Slice across chunk boundaries', () async {
      final block = Block((add) {
        add(Uint8List.fromList([1, 2, 3])); // Chunk 1
        add(Uint8List.fromList([4, 5, 6])); // Chunk 2
        add(Uint8List.fromList([7, 8, 9])); // Chunk 3
      });

      final slice = block.slice(2, 7); // [3,4,5,6,7]

      expect(slice.size, equals(5));
      final bytes = await slice.bytes();
      expect(bytes, equals([3, 4, 5, 6, 7]));
    });

    test('Negative index slicing', () async {
      final block = Block.fromBytes([
        Uint8List.fromList([1, 2, 3, 4, 5]),
      ]);

      // From 3rd last to last-1
      final slice = block.slice(-3, -1); // [3,4]

      expect(slice.size, equals(2));
      final bytes = await slice.bytes();
      expect(bytes, equals([3, 4]));
    });

    test('Omitting end index', () async {
      final block = Block.fromBytes([
        Uint8List.fromList([1, 2, 3, 4, 5]),
      ]);

      // From index 2 to end
      final slice = block.slice(2); // [3,4,5]

      expect(slice.size, equals(3));
      final bytes = await slice.bytes();
      expect(bytes, equals([3, 4, 5]));
    });

    test('Edge case - empty slice', () async {
      final block = Block.fromBytes([
        Uint8List.fromList([1, 2, 3]),
      ]);

      final slice = block.slice(1, 1); // Empty range

      expect(slice.size, equals(0));
      final bytes = await slice.bytes();
      expect(bytes, isEmpty);
    });

    test('Invalid slice range should throw error', () {
      final block = Block.fromBytes([
        Uint8List.fromList([1, 2, 3]),
      ]);

      // Start greater than end
      expect(() => block.slice(2, 1), throwsArgumentError);

      // Out of range
      expect(() => block.slice(-10), throwsArgumentError);
      expect(() => block.slice(5), throwsArgumentError);
    });

    test('Nested slicing', () async {
      final block = Block.fromBytes([
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      ]);

      final slice1 = block.slice(2, 8); // [3,4,5,6,7,8]
      final slice2 = slice1.slice(1, 4); // [4,5,6]

      expect(slice2.size, equals(3));
      final bytes = await slice2.bytes();
      expect(bytes, equals([4, 5, 6]));
    });
  });

  group('Performance and edge case tests', () {
    test('Lazy initialization - builder only executed when needed', () {
      var builderCalled = false;

      final block = Block((add) {
        builderCalled = true;
        add(Uint8List.fromList([1, 2, 3]));
      });

      // Builder should not be called before accessing size or stream
      expect(builderCalled, isFalse);

      // Accessing size will trigger initialization
      expect(block.size, equals(3));
      expect(builderCalled, isTrue);
    });

    test('Empty block slicing', () async {
      final block = Block.empty();
      final slice = block.slice(0, 0);

      expect(slice.size, equals(0));
      expect(await slice.bytes(), isEmpty);
    });
  });

  group('Caching mechanism tests', () {
    test('bytes() result should be cached', () async {
      int callCount = 0;

      final block = Block((add) {
        callCount++;
        add(Uint8List.fromList([1, 2, 3]));
      });

      // First call will execute the builder
      await block.bytes();
      expect(callCount, equals(1));

      // Second call should use cache
      await block.bytes();
      expect(callCount, equals(1)); // Builder should not be called again
    });

    test('text() result should be cached', () async {
      final block = Block.fromString(['Cache Test']);

      final text1 = await block.text();
      final text2 = await block.text();

      expect(identical(text1, text2), isTrue);
    });

    test('Sliced blocks should also use cache', () async {
      final block = Block.fromBytes([
        Uint8List.fromList([1, 2, 3, 4, 5]),
      ]);
      final slice = block.slice(1, 4); // [2,3,4]

      final bytes1 = await slice.bytes();
      final bytes2 = await slice.bytes();

      expect(identical(bytes1, bytes2), isTrue);
    });
  });

  group('Stream-based Block tests', () {
    test('Create Block from broadcast Stream', () async {
      final chunks = <Uint8List>[
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6, 7]),
      ];
      final stream = Stream.fromIterable(chunks);

      final block = Block.formStream(stream, 7);
      expect(block.size, equals(7));

      final result = await block.stream().toList();
      expect(result.length, equals(2));
      expect(result[0], equals([1, 2, 3]));
      expect(result[1], equals([4, 5, 6, 7]));
    });

    test('Stream size validation', () async {
      final chunks = <Uint8List>[
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6, 7]),
      ];
      final stream = Stream.fromIterable(chunks);
      final block = Block.formStream(stream, 10);

      expect(
        () => block.stream().toList(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Stream size mismatch'),
          ),
        ),
      );
    });

    test('Cached data after consuming the stream', () async {
      final chunks = <Uint8List>[
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5]),
      ];
      final stream = Stream.fromIterable(chunks);

      final block = Block.formStream(stream, 5);

      // 先消费成字节
      final bytes = await block.bytes();
      expect(bytes, equals([1, 2, 3, 4, 5]));

      // 确认已缓存 - 可以以其他形式获取
      final text = await block.text();
      expect(text.length, equals(5)); // 5 个字节
    });

    test('Stream-based block with empty stream', () async {
      final stream = Stream<Uint8List>.fromIterable([]);
      final block = Block.formStream(stream, 0);

      final bytes = await block.bytes();
      expect(bytes.length, equals(0));
    });

    test('Using bytes() with stream-based block', () async {
      // 创建广播流
      final chunks = <Uint8List>[
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5]),
      ];
      final stream = Stream.fromIterable(chunks);

      final block = Block.formStream(stream, 5);

      // 使用 bytes() 应当正确合并所有块
      final bytes = await block.bytes();
      expect(bytes, equals([1, 2, 3, 4, 5]));
    });
  });
}
