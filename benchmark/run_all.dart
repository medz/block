// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:benchmark_harness/benchmark_harness.dart';
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
  printSystemInfo();

  print('\n=== Block创建基准测试 ===');
  creation.main();

  print('\n=== Block操作基准测试 ===');
  operations.main();

  print('\n=== 数据去重基准测试 ===');
  deduplication.main();

  print('\n所有基准测试完成！');
}
