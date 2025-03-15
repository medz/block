// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('内存监控测试', () {
    setUp(() {
      // 重置状态
      Block.resetDataDeduplication();
    });

    test('内存监控器基本功能', () {
      print('初始内存: ${Block.totalMemoryUsage} bytes');

      // 启动内存监控器，设置较短的间隔时间以加快测试
      final stopMonitor = Block.startMemoryMonitor(
        intervalMs: 100,
        memoryLimit: 2 * 1024 * 1024, // 2MB
      );

      try {
        print('内存监控器启动成功');

        // 创建一些小块
        final List<Block> blocks = [];
        const blockSize = 100 * 1024; // 100KB
        const blockCount = 5;

        for (int i = 0; i < blockCount; i++) {
          final data = Uint8List(blockSize);
          for (int j = 0; j < blockSize; j++) {
            data[j] = (j + i) % 256;
          }

          final block = Block([data]);
          block.size; // 触发数据处理
          blocks.add(block);

          Block.forceUpdateMemoryStatistics();
          print('创建了 ${i + 1} 个块, 内存: ${Block.totalMemoryUsage} bytes');

          // 短暂等待，让内存监控器可能运行
          sleep(Duration(milliseconds: 200));
        }

        // 创建重复数据块触发去重
        print('\n创建重复数据块:');
        final duplicateData = Uint8List(blockSize);
        for (int j = 0; j < blockSize; j++) {
          duplicateData[j] = j % 256; // 与第一个块相同的数据
        }

        for (int i = 0; i < 3; i++) {
          final block = Block([duplicateData]);
          block.size; // 触发数据处理
          blocks.add(block);

          Block.forceUpdateMemoryStatistics();
          print('创建了第 ${i + 1} 个重复块, 内存: ${Block.totalMemoryUsage} bytes');
          print(
            '重复计数: ${Block.getDataDeduplicationDuplicateCount()}, 节省内存: ${Block.getDataDeduplicationSavedMemory()} bytes',
          );

          // 短暂等待，让内存监控器可能运行
          sleep(Duration(milliseconds: 200));
        }

        // 创建一个大块触发高内存
        print('\n创建大块触发高内存警告:');
        final largeData = Uint8List(1024 * 1024); // 1MB
        for (int i = 0; i < largeData.length; i++) {
          largeData[i] = i % 256;
        }

        final largeBlock = Block([largeData]);
        largeBlock.size; // 触发数据处理
        blocks.add(largeBlock);

        Block.forceUpdateMemoryStatistics();
        print('创建大块后内存: ${Block.totalMemoryUsage} bytes');

        // 等待足够长的时间让内存监控器运行几次
        sleep(Duration(seconds: 1));

        // 输出最终统计
        Block.forceUpdateMemoryStatistics();
        print('\n最终内存使用: ${Block.totalMemoryUsage} bytes');
        print('活跃块数量: ${Block.activeBlockCount}');

        final report = Block.getDataDeduplicationReport();
        print('\n数据去重报告:');
        print('uniqueBlockCount: ${report['uniqueBlockCount']}');
        print('totalBytes: ${report['totalBytes']}');
        print('totalRefCount: ${report['totalRefCount']}');
        print('totalSavedMemory: ${report['totalSavedMemory']}');
        print('duplicateBlockCount: ${report['duplicateBlockCount']}');

        // 测试手动触发垃圾回收
        print('\n测试手动触发内存清理:');
        Block.reduceMemoryUsage();
        sleep(Duration(milliseconds: 300));

        Block.forceUpdateMemoryStatistics();
        print('内存清理后: ${Block.totalMemoryUsage} bytes');
      } finally {
        // 停止内存监控器
        stopMonitor();
        print('内存监控器已停止');
      }
    });

    test('内存压力测试', () {
      print('初始内存: ${Block.totalMemoryUsage} bytes');

      // 启动内存监控器，设置较短的间隔时间
      final stopMonitor = Block.startMemoryMonitor(
        intervalMs: 100,
        // 设置较低的阈值以确保触发内存清理
        memoryLimit: 2 * 1024 * 1024, // 2MB
      );

      try {
        print('内存监控器启动成功');

        // 创建一系列块直到超过阈值
        final List<Block> blocks = [];
        const blockSize = 200 * 1024; // 200KB

        print('\n逐步增加内存压力:');
        for (int i = 0; i < 10; i++) {
          final data = Uint8List(blockSize);
          for (int j = 0; j < blockSize; j++) {
            data[j] = (j + i) % 256;
          }

          final block = Block([data]);
          block.size; // 触发数据处理
          blocks.add(block);

          Block.forceUpdateMemoryStatistics();
          print('创建了 ${i + 1} 个块, 内存: ${Block.totalMemoryUsage} bytes');

          // 等待监控器可能的反应
          sleep(Duration(milliseconds: 300));
        }

        // 最后的统计
        Block.forceUpdateMemoryStatistics();
        print('\n测试结束, 最终内存: ${Block.totalMemoryUsage} bytes');
        print('活跃块数量: ${Block.activeBlockCount}');

        // 释放一些块，模拟应用程序释放资源
        print('\n释放一部分块:');
        blocks.removeRange(0, 5);
        // 等待GC
        sleep(Duration(seconds: 1));
        Block.forceUpdateMemoryStatistics();
        print('释放5个块后内存: ${Block.totalMemoryUsage} bytes');
      } finally {
        // 停止内存监控器
        stopMonitor();
        print('内存监控器已停止');
      }
    });
  });
}

// 简单的睡眠函数
void sleep(Duration duration) {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {
    // 简单的忙等待
  }
}
