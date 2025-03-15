// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:block/block.dart';

/// 一个简单的程序，直接测试内存统计功能
void main() {
  print('开始测试内存统计功能...');

  // 重置数据去重统计
  Block.resetDataDeduplication();

  // 初始状态
  print('初始内存使用量: ${Block.totalMemoryUsage}');
  print('初始活跃Block数量: ${Block.activeBlockCount}');
  print('初始重复数据计数: ${Block.getDataDeduplicationDuplicateCount()}');
  print('初始节省内存: ${Block.getDataDeduplicationSavedMemory()}');

  // 创建一个数据对象
  final data = Uint8List(1024 * 1024); // 1MB
  for (int i = 0; i < data.length; i++) {
    data[i] = i % 256;
  }

  // 创建一个Block
  print('\n创建第一个Block...');
  final block1 = Block([data]);
  block1.size; // 触发数据处理

  // 检查内存使用情况
  print('创建Block1后:');
  print('内存使用量: ${Block.totalMemoryUsage}');
  print('活跃Block数量: ${Block.activeBlockCount}');
  print('重复数据计数: ${Block.getDataDeduplicationDuplicateCount()}');
  print('节省内存: ${Block.getDataDeduplicationSavedMemory()}');

  // 强制更新内存统计
  Block.forceUpdateMemoryStatistics();

  // 再次检查内存使用情况
  print('\n强制更新内存统计后:');
  print('内存使用量: ${Block.totalMemoryUsage}');
  print('活跃Block数量: ${Block.activeBlockCount}');
  print('重复数据计数: ${Block.getDataDeduplicationDuplicateCount()}');
  print('节省内存: ${Block.getDataDeduplicationSavedMemory()}');

  // 创建第二个相同的Block
  print('\n创建第二个Block（与第一个相同）...');
  final block2 = Block([data]);
  block2.size; // 触发数据处理

  // 检查内存使用情况
  print('创建Block2后:');
  print('内存使用量: ${Block.totalMemoryUsage}');
  print('活跃Block数量: ${Block.activeBlockCount}');
  print('重复数据计数: ${Block.getDataDeduplicationDuplicateCount()}');
  print('节省内存: ${Block.getDataDeduplicationSavedMemory()}');

  // 强制更新内存统计
  Block.forceUpdateMemoryStatistics();

  // 再次检查内存使用情况
  print('\n强制更新内存统计后:');
  print('内存使用量: ${Block.totalMemoryUsage}');
  print('活跃Block数量: ${Block.activeBlockCount}');
  print('重复数据计数: ${Block.getDataDeduplicationDuplicateCount()}');
  print('节省内存: ${Block.getDataDeduplicationSavedMemory()}');

  // 保持对Block的引用，防止垃圾回收
  print('\n测试完成。保持对Block的引用: ${block1.size}, ${block2.size}');
}
