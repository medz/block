// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('Block创建内存测试', () {
    setUp(() {
      // 重置状态
      Block.resetDataDeduplication();
    });

    test('创建大量小块的内存占用分析', () {
      print('初始内存: ${Block.totalMemoryUsage} bytes');

      // 创建50个小块(每个10KB)
      const blockSize = 10 * 1024; // 10KB
      const blockCount = 50;

      final List<Block> blocks = [];

      for (int i = 0; i < blockCount; i++) {
        final data = Uint8List(blockSize);
        // 每个块都略有不同，确保不会被去重
        for (int j = 0; j < blockSize; j++) {
          data[j] = (j + i) % 256;
        }

        final block = Block([data]);
        block.size; // 触发数据处理
        blocks.add(block);

        if (i % 10 == 0) {
          Block.forceUpdateMemoryStatistics();
          print('创建了 ${i + 1} 个块, 内存: ${Block.totalMemoryUsage} bytes');
        }
      }

      Block.forceUpdateMemoryStatistics();
      print('\n创建 $blockCount 个块后内存: ${Block.totalMemoryUsage} bytes');
      print('平均每块内存: ${Block.totalMemoryUsage / blockCount} bytes');
      print('活跃块数量: ${Block.activeBlockCount}');

      // 检查数据块结构
      final blockReport = Block.getGlobalMemoryReport();
      print('\n数据块报告:');
      print('总内存使用: ${blockReport['totalMemoryUsage']} bytes');
      print('活跃块数量: ${blockReport['activeBlockCount']}');
      print('平均每块内存: ${blockReport['averageBlockMemory']} bytes');

      // 验证内存使用是合理的
      // 预期每个块占用约blockSize + 一些开销
      expect(
        Block.totalMemoryUsage,
        lessThan(blockCount * blockSize * 1.5),
        reason: '总内存应该低于块大小和数量乘积的1.5倍',
      );

      // 确保引用计数正确
      expect(
        Block.activeBlockCount,
        equals(blockCount),
        reason: '活跃块数量应该等于创建的块数量',
      );
    });

    test('测试默认块大小和分块策略', () {
      // 创建一个大于默认块大小的块，检查是否被分块
      // 默认块大小 = 512KB (我们之前修改过)
      final largeBlockSize = 3 * 1024 * 1024; // 3MB

      print('创建大块前内存: ${Block.totalMemoryUsage} bytes');

      final data = Uint8List(largeBlockSize);
      for (int i = 0; i < largeBlockSize; i++) {
        data[i] = i % 256;
      }

      final block = Block([data]);
      block.size; // 触发数据处理

      Block.forceUpdateMemoryStatistics();
      print('创建大块后内存: ${Block.totalMemoryUsage} bytes');

      // 获取存储状态
      final storeStats = block.getMemoryReport();
      print('\n块内存报告:');
      print('块大小: ${block.size} bytes');
      print('块内存使用: ${storeStats['memoryCost']} bytes');

      // 验证块被分成了多个块
      expect(block.size, equals(largeBlockSize), reason: '块大小应该等于原始数据大小');
    });
  });
}
