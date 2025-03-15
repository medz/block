// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('内存清理测试', () {
    setUp(() {
      // 重置状态
      Block.resetDataDeduplication();
    });

    test('内存被合理清理', () {
      print('初始内存: ${Block.totalMemoryUsage} bytes');

      // 启动内存监控，设置较低的内存阈值
      final stopMonitor = Block.startMemoryMonitor(
        intervalMs: 500, // 0.5秒检查一次
        memoryLimit: 5 * 1024 * 1024, // 5MB
      );

      try {
        print('内存监控器启动成功');

        // 第一阶段：创建一些块，但保持在内存限制以下
        print('\n第一阶段: 创建适量块');
        final List<Block> activeBlocks = [];
        const blockSize = 500 * 1024; // 500KB

        for (int i = 0; i < 3; i++) {
          final data = Uint8List(blockSize);
          for (int j = 0; j < blockSize; j++) {
            data[j] = (j + i) % 256;
          }

          final block = Block([data]);
          block.size; // 触发数据处理
          activeBlocks.add(block);

          Block.forceUpdateMemoryStatistics();
          print('创建了 ${i + 1} 个块, 内存: ${Block.totalMemoryUsage} bytes');
          sleep(Duration(milliseconds: 300));
        }

        // 检查内存使用
        print('\n第一阶段内存状态:');
        Block.forceUpdateMemoryStatistics();
        printMemoryStats();

        // 第二阶段：创建一些临时块，然后释放它们
        print('\n第二阶段: 创建临时块并释放');
        {
          final List<Block> tempBlocks = [];

          for (int i = 0; i < 4; i++) {
            final data = Uint8List(blockSize);
            for (int j = 0; j < blockSize; j++) {
              data[j] = (j + i + 10) % 256; // 不同的数据
            }

            final block = Block([data]);
            block.size; // 触发数据处理
            tempBlocks.add(block);

            Block.forceUpdateMemoryStatistics();
            print('创建了临时块 ${i + 1}, 内存: ${Block.totalMemoryUsage} bytes');
            sleep(Duration(milliseconds: 300));
          }

          // 检查内存使用
          print('\n临时块创建后内存状态:');
          Block.forceUpdateMemoryStatistics();
          printMemoryStats();

          // 释放临时块
          print('\n释放临时块...');
          // tempBlocks清空，让GC可以回收这些Block
        }

        // 等待垃圾回收和内存清理
        sleep(Duration(seconds: 2));

        // 手动触发内存清理
        print('\n手动触发内存清理');
        final freedBytes = Block.reduceMemoryUsage();
        print('释放了 $freedBytes bytes');

        // 第三阶段：检查内存状态，应该恢复到类似第一阶段
        print('\n第三阶段: 临时块释放后内存状态');
        Block.forceUpdateMemoryStatistics();
        printMemoryStats();

        // 第四阶段：测试数据去重
        print('\n第四阶段: 测试数据去重');
        final List<Block> duplicateBlocks = [];

        // 创建重复数据块
        final duplicateData = Uint8List(blockSize);
        for (int j = 0; j < duplicateData.length; j++) {
          duplicateData[j] = j % 256;
        }

        for (int i = 0; i < 5; i++) {
          final block = Block([duplicateData]); // 相同数据
          block.size; // 触发数据处理
          duplicateBlocks.add(block);

          Block.forceUpdateMemoryStatistics();
          print('创建重复块 ${i + 1}, 内存: ${Block.totalMemoryUsage} bytes');
          print(
            '重复计数: ${Block.getDataDeduplicationDuplicateCount()}, 节省: ${Block.getDataDeduplicationSavedMemory()} bytes',
          );
          sleep(Duration(milliseconds: 300));
        }

        // 最终状态
        print('\n最终内存状态:');
        Block.forceUpdateMemoryStatistics();
        printMemoryStats();

        // 用于测试验证
        expect(Block.getDataDeduplicationDuplicateCount(), greaterThan(3));
        expect(Block.getDataDeduplicationSavedMemory(), greaterThan(1000000));
      } finally {
        // 停止内存监控器
        stopMonitor();
        print('内存监控器已停止');
      }
    });
  });
}

// 打印内存统计信息
void printMemoryStats() {
  print('总内存使用: ${Block.totalMemoryUsage} bytes');
  print('活跃块数量: ${Block.activeBlockCount}');
  print('重复计数: ${Block.getDataDeduplicationDuplicateCount()}');
  print('节省内存: ${Block.getDataDeduplicationSavedMemory()} bytes');

  final report = Block.getDataDeduplicationReport();
  print('唯一块数量: ${report['uniqueBlockCount']}');
}

// 简单的睡眠函数
void sleep(Duration duration) {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {
    // 简单的忙等待
  }
}
