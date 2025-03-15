// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:block/block.dart';
import 'package:block/src/memory_manager.dart';
import 'package:block/src/disposable_block.dart';

void main() {
  group('内存管理器测试', () {
    setUp(() {
      // 重置状态
      Block.resetDataDeduplication();
    });

    test('内存管理器基本功能', () {
      final manager = MemoryManager.instance;

      // 启动内存管理器
      manager.start(
        checkInterval: Duration(milliseconds: 100),
        highWatermark: 10 * 1024 * 1024, // 10MB
        criticalWatermark: 20 * 1024 * 1024, // 20MB
      );

      try {
        // 验证管理器已启动
        expect(manager, isNotNull);

        // 创建一个块并注册
        final blockId = 'test-block-1';
        final block = Object();
        manager.registerBlock(block, blockId);

        // 验证块被正确跟踪
        expect(manager.isBlockReferenced(blockId), isTrue);

        // 记录访问
        manager.recordBlockAccess(blockId);

        // 执行清理
        final freedBytes = manager.performCleanup();
        print('清理释放了 $freedBytes 字节');

        // 块应该仍然被引用
        expect(manager.isBlockReferenced(blockId), isTrue);

        // 执行强制清理
        final aggressiveFreedBytes = manager.performCleanup(aggressive: true);
        print('强制清理释放了 $aggressiveFreedBytes 字节');
      } finally {
        // 停止内存管理器
        manager.stop();
      }
    });

    test('DisposableBlock基本功能', () {
      // 创建一个可释放块
      final data = Uint8List(1024);
      for (int i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      final block = DisposableBlock([data]);

      // 验证基本属性
      expect(block.size, equals(1024));

      // 获取数据
      final bytes = block.toUint8List();
      expect(bytes.length, equals(1024));
      expect(bytes[0], equals(0));
      expect(bytes[100], equals(100));

      // 创建分片
      final slice = block.slice(100, 200);
      expect(slice.size, equals(100));

      final sliceBytes = slice.toUint8List();
      expect(sliceBytes.length, equals(100));
      expect(sliceBytes[0], equals(100));

      // 获取内存报告
      final report = block.getMemoryReport();
      expect(report, isNotNull);
      expect(report['memoryCost'], isNotNull);

      // 释放块
      block.dispose();

      // 验证块已释放
      expect(() => block.size, throwsStateError);
      expect(() => block.toUint8List(), throwsStateError);
    });

    test('DisposableBlock异步操作', () async {
      // 创建一个可释放块
      final data = Uint8List(1024);
      for (int i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      final block = DisposableBlock([data]);

      // 异步获取数据
      final bytes = await block.arrayBuffer();
      expect(bytes.length, equals(1024));

      // 转换为文本
      final text = await block.text();
      expect(text.length, greaterThan(0));

      // 流式读取
      final chunks = <Uint8List>[];
      await for (final chunk in block.stream()) {
        chunks.add(chunk);
      }

      expect(chunks.isNotEmpty, isTrue);
      int totalSize = 0;
      for (final chunk in chunks) {
        totalSize += chunk.length;
      }
      expect(totalSize, equals(1024));

      // 释放块
      block.dispose();

      // 验证块已释放
      expect(() => block.arrayBuffer(), throwsStateError);
      expect(() => block.text(), throwsStateError);
      expect(() => block.stream(), throwsStateError);
    });

    test('DisposableBlock内存管理', () {
      // 创建多个块
      final blocks = <DisposableBlock>[];

      for (int i = 0; i < 10; i++) {
        final data = Uint8List(100 * 1024); // 100KB
        for (int j = 0; j < data.length; j++) {
          data[j] = (i + j) % 256;
        }

        final block = DisposableBlock([data]);
        blocks.add(block);
      }

      // 验证所有块都可用
      for (final block in blocks) {
        expect(block.size, equals(100 * 1024));
      }

      // 释放一半的块
      for (int i = 0; i < 5; i++) {
        blocks[i].dispose();
      }

      // 验证释放的块不可用，未释放的块可用
      for (int i = 0; i < 10; i++) {
        if (i < 5) {
          expect(() => blocks[i].size, throwsStateError);
        } else {
          expect(blocks[i].size, equals(100 * 1024));
        }
      }

      // 释放剩余的块
      for (int i = 5; i < 10; i++) {
        blocks[i].dispose();
      }

      // 验证所有块都不可用
      for (final block in blocks) {
        expect(() => block.size, throwsStateError);
      }
    });
  });
}
