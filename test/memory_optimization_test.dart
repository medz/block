// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('内存优化测试', () {
    setUp(() {
      // 重置状态
      Block.resetDataDeduplication();
    });

    test('内存监控器会增加内存使用而不释放', () {
      // 这个测试检查是否内存监控器有问题
      print('初始内存状态:');
      print('内存使用: ${Block.totalMemoryUsage} bytes');

      // 设置内存限制，启动监控器
      Block.setMemoryUsageLimit(100 * 1024 * 1024); // 100MB

      final stopMonitor = Block.startMemoryMonitor(
        intervalMs: 500, // 较短的间隔，以便快速观察效果
        memoryLimit: 100 * 1024 * 1024,
      );

      // 创建一个块，然后检查内存状态
      final data = Uint8List(5 * 1024 * 1024); // 5MB
      for (int i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      Block? block = Block([data]);
      block.size; // 触发数据处理
      Block.forceUpdateMemoryStatistics();

      print('\n创建块后内存状态:');
      print('内存使用: ${Block.totalMemoryUsage} bytes');

      // 等待一会儿，让监控器运行几次
      print('\n等待监控器运行...');
      sleep(Duration(seconds: 2));

      // 检查内存状态是否稳定
      Block.forceUpdateMemoryStatistics();
      print('\n监控器运行后内存状态:');
      print('内存使用: ${Block.totalMemoryUsage} bytes');

      // 停止监控器，再次检查
      stopMonitor();
      Block.setMemoryUsageLimit(null);
      Block.forceUpdateMemoryStatistics();

      print('\n停止监控器后内存状态:');
      print('内存使用: ${Block.totalMemoryUsage} bytes');

      // 清理并强制垃圾回收
      block = null;
      sleep(Duration(seconds: 1));
      Block.forceUpdateMemoryStatistics();

      print('\n清理后内存状态:');
      print('内存使用: ${Block.totalMemoryUsage} bytes');
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
