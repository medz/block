// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'dart:convert';

import 'package:block/block.dart';
import 'package:test/test.dart';

void main() {
  group('Lazy Loading Tests', () {
    test('Block constructor should not process data immediately', () {
      // Prepare a large chunk of data
      final largeString = 'x' * 1000000; // 1MB of 'x' characters

      // Calculate timestamp before Block creation
      final startTime = DateTime.now();

      // Create a Block with the large data
      final block = Block([largeString]);

      // Calculate time spent to create Block
      final creationTime = DateTime.now().difference(startTime);

      // Verify Block creation was fast (data not processed yet)
      expect(
        creationTime.inMilliseconds,
        lessThan(50),
        reason: 'Block creation should be fast with lazy loading',
      );

      // Accessing size should trigger data processing
      final processingStartTime = DateTime.now();
      final size = block.size;
      final processingTime = DateTime.now().difference(processingStartTime);

      // Verify size is correct
      expect(
        size,
        greaterThan(0),
        reason: 'Size should be correct after processing',
      );

      // Verify processing took some time (more than creation)
      expect(
        processingTime.inMilliseconds,
        greaterThan(creationTime.inMilliseconds),
        reason: 'Data processing should take longer than Block creation',
      );

      // Second access to size should be fast (cached)
      final cachedAccessStartTime = DateTime.now();
      final cachedSize = block.size;
      final cachedAccessTime = DateTime.now().difference(cachedAccessStartTime);

      // Verify cached access is fast
      expect(
        cachedAccessTime.inMilliseconds,
        lessThan(processingTime.inMilliseconds),
        reason: 'Second access to size should be faster (cached)',
      );

      // Verify size is still correct
      expect(
        cachedSize,
        equals(size),
        reason: 'Cached size should match original size',
      );
    });

    test('Block.slice() should trigger data processing', () {
      final data = 'Hello, world!';
      final block = Block([data]);

      // Slicing should trigger data processing
      final slice = block.slice(7, 12); // "world"

      // Verify slice size
      expect(slice.size, equals(5), reason: 'Slice size should be correct');

      // Verify slice content
      slice.text().then((text) {
        expect(
          text,
          equals('world'),
          reason: 'Slice content should be correct',
        );
      });
    });

    test('Multiple Block methods should all work with lazy loading', () async {
      final data = Uint8List.fromList(
        utf8.encode('Test data for lazy loading'),
      );
      final block = Block([data]);

      // Test various methods
      final byteView = block.getByteDataView();
      expect(
        byteView.length,
        equals(data.length),
        reason: 'ByteDataView should have correct length',
      );

      final buffer = await block.arrayBuffer();
      expect(
        buffer.length,
        equals(data.length),
        reason: 'arrayBuffer() should return correct data',
      );

      final text = await block.text();
      expect(
        text,
        equals('Test data for lazy loading'),
        reason: 'text() should return correct content',
      );

      final directData = block.getDirectData();
      expect(
        directData,
        isNotNull,
        reason: 'getDirectData() should return data for single chunk',
      );
      if (directData != null) {
        expect(
          directData.length,
          equals(data.length),
          reason: 'Direct data should have correct length',
        );
      }
    });

    test(
      'Large Block should benefit from lazy loading when only part is accessed',
      () async {
        // Create a large Block with multiple parts
        final part1 = 'a' * 100000;
        final part2 = 'b' * 200000;
        final part3 = 'c' * 300000;

        final block = Block([part1, part2, part3]);

        // Only access a slice of the Block
        final slice = block.slice(100000, 100100); // 100 bytes from part2

        // Verify slice has correct size
        expect(slice.size, equals(100), reason: 'Slice size should be correct');

        // Verify slice content
        final sliceText = await slice.text();
        expect(
          sliceText,
          equals('b' * 100),
          reason: 'Slice content should be correct',
        );
      },
    );
  });
}
