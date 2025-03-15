// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:block/block.dart';
import 'framework.dart';

// 导入所有基准测试
import 'block_creation_benchmark.dart' as creation;
import 'block_operations_benchmark.dart' as operations;
import 'deduplication_benchmark.dart' as deduplication;

/// 为文本添加颜色（终端输出）
String colorText(String text, int colorCode) {
  return '\x1B[${colorCode}m$text\x1B[0m';
}

/// 打印日期和时间标题
void printDateTimeHeader() {
  final now = DateTime.now();
  final formattedDateTime =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

  print(colorText('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 36));
  print(colorText('Block 基准测试 - $formattedDateTime', 32));
  print(colorText('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n', 36));
}

/// 打印系统信息
void printSystemInfo() {
  print('=== 系统信息 ===');
  print('操作系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  print('Dart版本: ${Platform.version}');
  print('CPU核心数: ${Platform.numberOfProcessors}');
  print('===============\n');
}

/// 打印测试组标题
void printTestGroupHeader(String title) {
  print(colorText('\n▶ $title', 35));
  print(colorText('--------------------------------', 90));
}

/// 运行所有基准测试
void main() {
  printDateTimeHeader();
  printSystemInfo();

  // 重置数据去重统计，为所有测试提供统一的起点
  Block.resetDataDeduplication();

  print(colorText('\n=== Block创建基准测试 ===', 32));
  creation.main();

  print(colorText('\n=== Block操作基准测试 ===', 32));
  operations.main();

  print(colorText('\n=== 数据去重基准测试 ===', 32));
  deduplication.main();

  // 单独为最终验证测试重置数据去重统计
  Block.resetDataDeduplication();

  // 进行数据去重实际测试
  testDeduplication();

  print(colorText('\n所有基准测试完成！', 32));
}

/// 进行实际的数据去重测试，检验数据去重功能
void testDeduplication() {
  print(colorText('\n=== 数据去重功能验证 ===', 35));

  // 重置数据去重统计
  Block.resetDataDeduplication();

  // 创建一个数据对象
  final data = Uint8List(1 * 1024 * 1024); // 1MB
  for (int i = 0; i < data.length; i++) {
    data[i] = i % 256;
  }

  print('创建10个相同数据的Block...');
  final blocks = <Block>[];

  // 创建10个Block，每个都包含相同的数据
  for (int i = 0; i < 10; i++) {
    final block = Block([data]);
    block.size; // 触发数据处理
    blocks.add(block);

    // 输出去重进度
    if (i > 0 && i % 2 == 0) {
      // 强制更新内存统计
      Block.forceUpdateMemoryStatistics();

      print(
        '已创建 ${i + 1} 个Block，当前重复计数: ${Block.getDataDeduplicationDuplicateCount()}',
      );
    }
  }

  // 强制更新内存统计
  Block.forceUpdateMemoryStatistics();

  // 输出最终统计
  final duplicateCount = Block.getDataDeduplicationDuplicateCount();
  final savedMemory = Block.getDataDeduplicationSavedMemory();
  final report = Block.getDataDeduplicationReport();

  print(colorText('\n=== 数据去重结果 ===', 36));
  print('重复块数量: $duplicateCount');
  print('节省内存: ${(savedMemory / 1024 / 1024).toStringAsFixed(2)} MB');
  print('唯一块数量: ${report['uniqueBlockCount']}');
  print('总字节数: ${report['totalBytes']}');
  print('总引用计数: ${report['totalRefCount']}');

  // 计算去重效率
  if (report['totalBytes'] > 0) {
    final efficiency = (savedMemory / (report['totalBytes'] * 1)) * 100;
    print('去重效率: ${efficiency.toStringAsFixed(2)}%');
  }

  // 清理资源，确保数据被释放
  blocks.clear();
}
