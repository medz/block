// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:test/test.dart';

void main() {
  group('Block', () {
    test('creates a block with data', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final block = Block([data]);

      expect(block.size, equals(4));
      expect(block.type, equals(''));
    });

    test('creates a block with data and type', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final block = Block([data], type: 'application/octet-stream');

      expect(block.size, equals(4));
      expect(block.type, equals('application/octet-stream'));
    });

    test('creates an empty block', () {
      final block = Block([]);

      expect(block.size, equals(0));
      expect(block.type, equals(''));
    });

    test('creates an empty block with type', () {
      final block = Block([], type: 'application/octet-stream');

      expect(block.size, equals(0));
      expect(block.type, equals('application/octet-stream'));
    });

    test('creates block from empty list using convenience method', () {
      final block = Block.empty(type: 'text/plain');

      expect(block.size, equals(0));
      expect(block.type, equals('text/plain'));
    });

    test('converts to Uint8List using arrayBuffer', () async {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final block = Block([data]);

      final result = await block.arrayBuffer();
      expect(result, equals(data));
    });

    test('creates slice', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final block = Block([data]);

      final slice = block.slice(1, 4);
      expect(slice.size, equals(3));
      expect(slice.type, equals(''));
    });

    test('creates slice with custom content type', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final block = Block([data]);

      final slice = block.slice(1, 4, 'application/custom');
      expect(slice.size, equals(3));
      expect(slice.type, equals('application/custom'));
    });

    test('slice converts to correct data', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final block = Block([data]);

      final slice = block.slice(1, 4);
      final sliceData = await slice.arrayBuffer();

      expect(sliceData, equals(Uint8List.fromList([2, 3, 4])));
    });

    test('handles negative slice indices', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final block = Block([data]);

      final slice = block.slice(-3, -1);
      final sliceData = await slice.arrayBuffer();

      expect(sliceData, equals(Uint8List.fromList([3, 4])));
    });

    test('creates from list of parts', () async {
      final parts = [
        'Hello, ',
        Uint8List.fromList(utf8.encode('world')),
        Block([Uint8List.fromList(utf8.encode('!'))]),
      ];

      final block = Block(parts, type: 'text/plain');

      expect(block.size, equals(13));
      expect(block.type, equals('text/plain'));

      final data = await block.arrayBuffer();
      expect(utf8.decode(data), equals('Hello, world!'));
    });

    test('converts to text', () async {
      final block = Block(['Hello, world!']);
      final text = await block.text();
      expect(text, equals('Hello, world!'));
    });

    test('streams data in chunks', () async {
      final data = Uint8List(100 * 1024); // 100KB
      // Fill with sequential numbers for testing
      for (int i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      final block = Block([data]);
      final chunks = <Uint8List>[];

      await for (final chunk in block.stream(chunkSize: 10 * 1024)) {
        chunks.add(chunk);
      }

      // Should split into 10 chunks of 10KB each
      expect(chunks.length, equals(10));

      // Combine chunks and compare with original
      final combined = Uint8List(100 * 1024);
      int offset = 0;
      for (final chunk in chunks) {
        combined.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      expect(combined, equals(data));
    });

    test('handles string parts encoding', () {
      final block = Block(['Hello', ' ', 'World']);
      expect(block.size, equals(11));
    });

    test('handles ByteData parts', () {
      final buffer = Uint8List(4).buffer;
      final byteData =
          ByteData.view(buffer)
            ..setUint8(0, 1)
            ..setUint8(1, 2)
            ..setUint8(2, 3)
            ..setUint8(3, 4);

      final block = Block([byteData]);
      expect(block.size, equals(4));
    });

    test('throws on unsupported part types', () {
      expect(() => Block([123]), throwsArgumentError);
      expect(() => Block([null]), throwsArgumentError);
      expect(() => Block([{}]), throwsArgumentError);
    });
  });

  group('Zero-copy optimizations', () {
    test('slice method should not copy data for nested slices', () {
      // 创建一个大的原始数据块
      final originalData = Uint8List(1000000);
      for (int i = 0; i < originalData.length; i++) {
        originalData[i] = i % 256;
      }

      // 创建原始Block
      final originalBlock = Block([originalData]);
      expect(originalBlock.size, equals(1000000));

      // 创建第一层切片
      final slice1 = originalBlock.slice(100000, 900000);
      expect(slice1.size, equals(800000));

      // 创建第二层切片
      final slice2 = slice1.slice(100000, 700000);
      expect(slice2.size, equals(600000));

      // 创建第三层切片
      final slice3 = slice2.slice(100000, 500000);
      expect(slice3.size, equals(400000));

      // 验证最终切片内容正确
      slice3.arrayBuffer().then((data) {
        expect(data.length, equals(400000));

        // 验证数据正确性 - 应该从原始数据的300000偏移开始
        for (int i = 0; i < data.length; i++) {
          expect(data[i], equals((i + 300000) % 256));
        }
      });
    });

    test('stream method should efficiently stream sliced data', () async {
      // 创建一个大的原始数据块
      final originalData = Uint8List(1000000);
      for (int i = 0; i < originalData.length; i++) {
        originalData[i] = i % 256;
      }

      // 创建原始Block
      final originalBlock = Block([originalData]);

      // 创建多层嵌套切片
      final slice1 = originalBlock.slice(200000, 800000);
      final slice2 = slice1.slice(100000, 500000);

      // 使用stream获取数据
      final chunks = <Uint8List>[];
      await for (final chunk in slice2.stream(chunkSize: 50000)) {
        chunks.add(chunk);
      }

      // 验证总数据量正确
      final totalBytes = chunks.fold<int>(
        0,
        (sum, chunk) => sum + chunk.length,
      );
      expect(totalBytes, equals(400000));

      // 重新组合数据并验证内容
      final combinedData = Uint8List(totalBytes);
      int offset = 0;
      for (final chunk in chunks) {
        combinedData.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      // 验证数据正确性 - 应该从原始数据的300000偏移开始
      for (int i = 0; i < combinedData.length; i++) {
        expect(combinedData[i], equals((i + 300000) % 256));
      }
    });
  });
}
