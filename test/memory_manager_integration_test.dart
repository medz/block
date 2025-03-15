// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('内存管理集成测试', () {
    setUp(() {
      // 启动内存管理器，设置适当的阈值
      MemoryManager.instance.start(
        checkInterval: const Duration(seconds: 1),
        highWatermark: 10 * 1024 * 1024, // 10MB
        criticalWatermark: 20 * 1024 * 1024, // 20MB
      );
    });

    tearDown(() {
      // 停止内存管理器
      MemoryManager.instance.stop();
    });

    test('MemoryManager跟踪Block访问', () {
      // 创建一个Block
      final block = Block([Uint8List(1024 * 100)]); // 100KB数据
      final blockId = block.hashCode.toString();

      // 验证Block已经被注册到MemoryManager
      expect(MemoryManager.instance.isBlockReferenced(blockId), isTrue);

      // 访问Block的不同方法，确保记录访问
      block.size;
      expect(
        MemoryManager.instance.getMemoryReport()['trackedBlockCount'],
        1,
        reason: '应该跟踪1个Block',
      );

      // 创建Block的分片，再次验证跟踪
      final slice = block.slice(0, 1024);
      expect(
        MemoryManager.instance.getMemoryReport()['trackedBlockCount'],
        2,
        reason: '分片应该作为独立Block被跟踪',
      );

      // 验证内存使用估计不为零
      expect(
        MemoryManager.instance.getEstimatedMemoryUsage(),
        greaterThan(0),
        reason: '内存使用估计应该大于0',
      );
    });

    test('DisposableBlock显式释放功能', () {
      // 创建DisposableBlock
      final disposableBlock = DisposableBlock([Uint8List(1024 * 200)]); // 200KB
      final size = disposableBlock.size;
      expect(size, 1024 * 200, reason: 'DisposableBlock大小应为200KB');

      // 获取当前内存使用估计
      final initialMemoryUsage =
          MemoryManager.instance.getEstimatedMemoryUsage();
      expect(initialMemoryUsage, greaterThan(0), reason: '内存使用估计应该大于0');

      // 显式释放DisposableBlock
      disposableBlock.dispose();

      // 尝试访问已释放的Block应该抛出异常
      expect(() => disposableBlock.size, throwsStateError);

      // 执行内存清理
      final freedBytes = MemoryManager.instance.performCleanup();
      expect(freedBytes, greaterThan(0), reason: '应该释放一些内存');

      // 验证内存使用减少
      expect(
        MemoryManager.instance.getEstimatedMemoryUsage(),
        lessThan(initialMemoryUsage),
        reason: '内存使用应该减少',
      );
    });

    test('Block内存统计功能', () {
      // 创建多个Block
      final blocks = <Block>[];
      for (int i = 0; i < 5; i++) {
        blocks.add(Block([Uint8List(1024 * 100)])); // 每个100KB
      }

      // 确保所有Block的数据都被加载
      for (final block in blocks) {
        block.size;
      }

      // 获取内存报告
      final report = MemoryManager.instance.getMemoryReport();
      print('内存报告: $report');

      // 验证有意义的内存使用报告
      expect(report['trackedBlockCount'], 5, reason: '应该有5个被跟踪的Block');
      expect(
        report['estimatedMemoryUsage'],
        greaterThan(0),
        reason: '内存使用估计应该大于0',
      );
    });
  });
}
