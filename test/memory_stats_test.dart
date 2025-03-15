// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:block/block.dart';
import 'package:test/test.dart';

void main() {
  group('Memory Statistics Tests', () {
    setUp(() {
      // 重置数据去重统计
      Block.resetDataDeduplication();
    });

    test('Memory usage is tracked correctly', () {
      // 初始状态
      print('Initial memory usage: ${Block.totalMemoryUsage}');
      print('Initial active blocks: ${Block.activeBlockCount}');
      print(
        'Initial duplicate count: ${Block.getDataDeduplicationDuplicateCount()}',
      );
      print('Initial saved memory: ${Block.getDataDeduplicationSavedMemory()}');

      // 创建一个Block
      final data = Uint8List(1024 * 1024); // 1MB
      for (int i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      final block1 = Block([data]);
      block1.size; // 触发数据处理

      // 检查内存使用情况
      print('After creating block1:');
      print('Memory usage: ${Block.totalMemoryUsage}');
      print('Active blocks: ${Block.activeBlockCount}');
      print('Duplicate count: ${Block.getDataDeduplicationDuplicateCount()}');
      print('Saved memory: ${Block.getDataDeduplicationSavedMemory()}');

      // 创建第二个相同的Block
      final block2 = Block([data]);
      block2.size; // 触发数据处理

      // 检查内存使用情况
      print('After creating block2:');
      print('Memory usage: ${Block.totalMemoryUsage}');
      print('Active blocks: ${Block.activeBlockCount}');
      print('Duplicate count: ${Block.getDataDeduplicationDuplicateCount()}');
      print('Saved memory: ${Block.getDataDeduplicationSavedMemory()}');

      // 强制更新内存统计
      Block.forceUpdateMemoryStatistics();

      // 再次检查内存使用情况
      print('After forcing update:');
      print('Memory usage: ${Block.totalMemoryUsage}');
      print('Active blocks: ${Block.activeBlockCount}');
      print('Duplicate count: ${Block.getDataDeduplicationDuplicateCount()}');
      print('Saved memory: ${Block.getDataDeduplicationSavedMemory()}');

      // 验证内存统计
      expect(Block.activeBlockCount, 2);
      expect(Block.getDataDeduplicationDuplicateCount(), greaterThan(0));
      expect(Block.getDataDeduplicationSavedMemory(), greaterThan(0));
    });

    test('Data deduplication works correctly', () {
      // 创建10个相同的Block
      final data = Uint8List(1024 * 1024); // 1MB
      for (int i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      final blocks = <Block>[];
      for (int i = 0; i < 10; i++) {
        final block = Block([data]);
        block.size; // 触发数据处理
        blocks.add(block);
      }

      // 强制更新内存统计
      Block.forceUpdateMemoryStatistics();

      // 检查内存使用情况
      print('After creating 10 identical blocks:');
      print('Memory usage: ${Block.totalMemoryUsage}');
      print('Active blocks: ${Block.activeBlockCount}');
      print('Duplicate count: ${Block.getDataDeduplicationDuplicateCount()}');
      print('Saved memory: ${Block.getDataDeduplicationSavedMemory()}');

      // 验证内存统计
      expect(Block.activeBlockCount, greaterThanOrEqualTo(10));
      expect(Block.getDataDeduplicationDuplicateCount(), greaterThan(0));
      expect(Block.getDataDeduplicationSavedMemory(), greaterThan(0));
    });
  });
}
