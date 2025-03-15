// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';

void main() {
  group('Memory Management Optimization Tests', () {
    setUp(() {
      // 启动内存管理器，设置适当的阈值
      MemoryManager.instance.start(
        checkInterval: const Duration(seconds: 1),
        highWatermark: 10 * 1024 * 1024, // 10MB
        criticalWatermark: 20 * 1024 * 1024, // 20MB
      );

      // Reset statistics
      DataStore.instance.resetStatistics();
      Block.resetDataDeduplication();
    });

    tearDown(() {
      // 停止内存管理器
      MemoryManager.instance.stop();
    });

    test('MemoryManager tracks Block access correctly', () {
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
      block.slice(0, 1024);
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

    test('MemoryManager cleans up unreferenced blocks', () async {
      // 创建一组临时Block
      var blocks = <Block>[];
      for (int i = 0; i < 5; i++) {
        blocks.add(Block([Uint8List(1024 * 100)])); // 每个100KB
      }

      // 记录当前跟踪的Block数量
      final initialCount = MemoryManager.instance.getTrackedBlockCount();
      expect(initialCount, 5, reason: '应该有5个被跟踪的Block');

      // 移除对Block的引用
      blocks.clear();

      // 强制垃圾回收
      await _triggerGC();

      // 执行内存清理
      final freedBytes = MemoryManager.instance.performCleanup();
      expect(freedBytes, greaterThan(0), reason: '应该释放一些内存');

      // 验证跟踪的Block数量减少
      // 注意：垃圾回收是不确定的，所以这个测试可能偶尔失败
      // 如果测试不稳定，可以考虑使用DisposableBlock代替
      expect(
        MemoryManager.instance.getTrackedBlockCount(),
        lessThan(initialCount),
        reason: '跟踪的Block数量应该减少',
      );
    });

    test('DisposableBlock explicit disposal works correctly', () {
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

    test(
      'DataStore integrates with MemoryManager for orphaned data cleanup',
      () {
        // 创建一些Block对象
        final block1 = Block([Uint8List(1024 * 50)]); // 50KB
        final block2 = Block([Uint8List(1024 * 50)]); // 50KB

        // 确保数据被加载
        block1.size;
        block2.size;

        // 验证数据关联被正确跟踪
        expect(
          MemoryManager.instance.getTrackedDataCount(),
          greaterThan(0),
          reason: '应该有跟踪的数据块',
        );

        // 执行孤立数据清理
        final freedBytes = DataStore.instance.cleanOrphanedData();

        // 由于Block仍在引用数据，应该没有数据被清理
        expect(freedBytes, 0, reason: '没有孤立数据，不应释放内存');
      },
    );
  });
}

// 尝试触发垃圾回收
// 注意：Dart不保证垃圾回收会立即执行
Future<void> _triggerGC() async {
  // 创建一些对象然后丢弃它们
  List<List<int>> lists = [];
  for (int i = 0; i < 1000; i++) {
    lists.add(List<int>.filled(1000, i));
  }
  lists.clear();

  // 等待一段时间，希望垃圾回收发生
  await Future.delayed(const Duration(seconds: 2));
}
