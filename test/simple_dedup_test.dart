// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('简单数据去重测试', () {
    setUp(() {
      // 重置状态，确保没有残留影响
      Block.resetDataDeduplication();
    });

    test('小块相同数据只存储一次', () {
      // 使用足够小的数据避免分块
      final testDataSize = 100 * 1024; // 100KB，这样小就不会被分块
      final data = Uint8List(testDataSize);
      for (int i = 0; i < testDataSize; i++) {
        data[i] = i % 256;
      }

      // 打印数据去重系统初始状态
      print('---- 初始状态 ----');
      final initialReport = Block.getDataDeduplicationReport();
      print('数据去重报告: $initialReport');
      print('总内存使用: ${Block.totalMemoryUsage} bytes');

      // 创建第一个Block
      final block1 = Block([data]);
      block1.size; // 触发数据处理

      // 打印第一个块后的状态
      print('\n---- 添加第一个块后 ----');
      Block.forceUpdateMemoryStatistics();
      final afterFirstReport = Block.getDataDeduplicationReport();
      print('数据去重报告: $afterFirstReport');
      print('总内存使用: ${Block.totalMemoryUsage} bytes');

      // 创建第二个相同数据的Block
      final block2 = Block([data]);
      block2.size; // 触发数据处理

      // 打印第二个块后的状态
      print('\n---- 添加第二个块后 ----');
      Block.forceUpdateMemoryStatistics();
      final afterSecondReport = Block.getDataDeduplicationReport();
      print('数据去重报告: $afterSecondReport');
      print('总内存使用: ${Block.totalMemoryUsage} bytes');
      print('重复数据计数: ${Block.getDataDeduplicationDuplicateCount()}');
      print('节省的内存: ${Block.getDataDeduplicationSavedMemory()} bytes');

      // 验证重复计数和内存节省
      final duplicateCount = Block.getDataDeduplicationDuplicateCount();
      expect(duplicateCount, greaterThan(0), reason: '应该检测到重复数据');

      final savedMemory = Block.getDataDeduplicationSavedMemory();
      expect(savedMemory, greaterThan(0), reason: '应该节省了内存');

      // 创建10个相同数据的Block，验证内存不会线性增长
      print('\n---- 添加10个相同数据的块 ----');
      final blocksBeforeTen = Block.activeBlockCount;
      final memoryBeforeTen = Block.totalMemoryUsage;

      final tenBlocks = List.generate(10, (_) {
        final b = Block([data]);
        b.size; // 触发数据处理
        return b;
      });

      Block.forceUpdateMemoryStatistics();
      final blocksAfterTen = Block.activeBlockCount;
      final memoryAfterTen = Block.totalMemoryUsage;

      print('块数量增加: ${blocksAfterTen - blocksBeforeTen}');
      print('内存增加: ${memoryAfterTen - memoryBeforeTen} bytes');
      print('平均每块内存: ${(memoryAfterTen - memoryBeforeTen) / 10} bytes');

      // 验证添加10个块的内存增长远小于预期
      // 如果没有去重，预期增长为10*testDataSize
      // 有去重的情况下，增长应该主要是元数据，远小于数据本身
      expect(
        memoryAfterTen - memoryBeforeTen,
        lessThan(10 * testDataSize / 2),
        reason: '添加10个相同数据的块，内存增长应该远小于全部数据大小',
      );

      // 保持块的引用，避免垃圾回收
      expect(tenBlocks.length, 10);
    });
  });
}
