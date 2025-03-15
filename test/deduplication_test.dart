// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('Block 内存占用测试', () {
    setUp(() {
      // 重置状态，确保没有残留影响
      Block.resetDataDeduplication();
    });

    test('相同数据只存储一次', () {
      // 准备2MB测试数据
      final testDataSize = 2 * 1024 * 1024;
      final data = Uint8List(testDataSize);
      for (int i = 0; i < testDataSize; i++) {
        data[i] = i % 256;
      }

      // 统计初始内存使用
      final initialMemory = Block.totalMemoryUsage;
      print('初始内存使用: $initialMemory bytes');

      // 创建第一个Block
      final block1 = Block([data]);
      block1.size; // 触发数据处理

      // 统计第一个Block后的内存使用
      final afterFirstBlock = Block.totalMemoryUsage;
      print('添加第一个Block后内存使用: $afterFirstBlock bytes');
      print('第一个Block增加的内存: ${afterFirstBlock - initialMemory} bytes');

      // 创建第二个Block，使用相同数据
      final block2 = Block([data]);
      block2.size; // 触发数据处理

      // 统计第二个Block后的内存使用
      Block.forceUpdateMemoryStatistics(); // 强制更新统计
      final afterSecondBlock = Block.totalMemoryUsage;
      print('添加第二个Block后内存使用: $afterSecondBlock bytes');
      print('第二个Block增加的内存: ${afterSecondBlock - afterFirstBlock} bytes');

      // 去重统计
      final duplicateCount = Block.getDataDeduplicationDuplicateCount();
      final savedMemory = Block.getDataDeduplicationSavedMemory();
      print('重复数据计数: $duplicateCount');
      print('节省的内存: $savedMemory bytes');

      // 验证:
      // 1. 添加第二个块后内存增加量应该明显小于第一个块
      // 2. 去重计数应该为1(表示有1个块被去重)
      // 3. 节省的内存应该接近于块的大小(2MB)

      expect(duplicateCount, 1, reason: '应该检测到1个重复块');
      expect(savedMemory, greaterThan(0), reason: '应该有内存节省');
      expect(
        savedMemory,
        closeTo(testDataSize, testDataSize * 0.1),
        reason: '节省的内存应接近块大小',
      );

      // 内存增加验证(考虑到元数据开销，使用近似比较)
      expect(
        afterSecondBlock - afterFirstBlock,
        lessThan((afterFirstBlock - initialMemory) * 0.2),
        reason: '第二个块的内存增加应远小于第一个块',
      );
    });

    test('不同数据存储为独立块', () {
      // 准备两个不同的2MB测试数据
      final testDataSize = 2 * 1024 * 1024;
      final data1 = Uint8List(testDataSize);
      final data2 = Uint8List(testDataSize);

      for (int i = 0; i < testDataSize; i++) {
        data1[i] = i % 256;
        data2[i] = (i + 128) % 256; // 不同的数据
      }

      // 统计初始内存使用
      final initialMemory = Block.totalMemoryUsage;

      // 创建两个Block
      final block1 = Block([data1]);
      block1.size; // 触发数据处理

      final afterFirstBlock = Block.totalMemoryUsage;

      final block2 = Block([data2]);
      block2.size; // 触发数据处理

      // 统计并验证
      Block.forceUpdateMemoryStatistics();
      final afterSecondBlock = Block.totalMemoryUsage;
      final duplicateCount = Block.getDataDeduplicationDuplicateCount();
      final savedMemory = Block.getDataDeduplicationSavedMemory();

      print('不同数据 - 重复计数: $duplicateCount');
      print('不同数据 - 节省内存: $savedMemory bytes');
      print('不同数据 - 第一个块增加的内存: ${afterFirstBlock - initialMemory} bytes');
      print('不同数据 - 第二个块增加的内存: ${afterSecondBlock - afterFirstBlock} bytes');

      // 验证:
      // 1. 不应该检测到任何重复
      // 2. 两个块都应该占用相似的内存

      expect(duplicateCount, 0, reason: '不应检测到重复块');
      expect(savedMemory, 0, reason: '不应有内存节省');

      // 两个不同块应该占用相似内存(考虑到元数据开销，使用近似比较)
      final firstBlockMemory = afterFirstBlock - initialMemory;
      final secondBlockMemory = afterSecondBlock - afterFirstBlock;
      expect(
        secondBlockMemory,
        closeTo(firstBlockMemory, firstBlockMemory * 0.2),
        reason: '两个不同块应占用相似内存',
      );
    });
  });
}
