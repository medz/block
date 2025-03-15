// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:block/block.dart';

/// 定义内存使用基准测试接口
abstract class MemoryBenchmark extends BenchmarkBase {
  /// 测试执行前的内存使用量
  int _memoryBefore = 0;

  /// 测试执行后的内存使用量
  int _memoryAfter = 0;

  /// 记录Block总内存使用量历史
  final List<int> _memoryUsageHistory = [];

  /// 记录活跃Block数量历史
  final List<int> _activeBlockHistory = [];

  /// 创建内存基准测试
  MemoryBenchmark(String name) : super(name);

  @override
  void setUp() {
    // 记录初始内存使用量
    _memoryBefore = Block.totalMemoryUsage;
    _memoryUsageHistory.clear();
    _activeBlockHistory.clear();
    _memoryUsageHistory.add(_memoryBefore);
    _activeBlockHistory.add(Block.activeBlockCount);
  }

  @override
  void tearDown() {
    // 记录测试后内存使用量
    _memoryAfter = Block.totalMemoryUsage;
    _memoryUsageHistory.add(_memoryAfter);
    _activeBlockHistory.add(Block.activeBlockCount);

    // 输出内存使用情况
    print(
      'Memory usage: before=${_memoryBefore} bytes, after=${_memoryAfter} bytes',
    );
    print('Memory diff: ${_memoryAfter - _memoryBefore} bytes');
    print('Active blocks: ${Block.activeBlockCount}');
  }

  /// 获取最大内存使用量
  int get peakMemoryUsage =>
      _memoryUsageHistory.isEmpty
          ? 0
          : _memoryUsageHistory.reduce((a, b) => a > b ? a : b);

  /// 获取最大活跃Block数量
  int get peakActiveBlocks =>
      _activeBlockHistory.isEmpty
          ? 0
          : _activeBlockHistory.reduce((a, b) => a > b ? a : b);

  /// 在测试执行过程中记录内存使用点
  void recordMemoryPoint() {
    _memoryUsageHistory.add(Block.totalMemoryUsage);
    _activeBlockHistory.add(Block.activeBlockCount);
  }
}

/// 生成测试数据
class TestDataGenerator {
  /// 生成指定大小的随机数据
  static Uint8List generateRandomData(int size) {
    final data = Uint8List(size);
    final random = Random();
    for (int i = 0; i < size; i++) {
      data[i] = random.nextInt(256);
    }
    return data;
  }

  /// 生成指定大小的顺序数据
  static Uint8List generateSequentialData(int size) {
    final data = Uint8List(size);
    for (int i = 0; i < size; i++) {
      data[i] = i % 256;
    }
    return data;
  }

  /// 生成特定模式的数据以最大化数据去重
  static Uint8List generateDuplicateData(int size, int patternSize) {
    final pattern = Uint8List(patternSize);
    for (int i = 0; i < patternSize; i++) {
      pattern[i] = i % 256;
    }

    final data = Uint8List(size);
    for (int i = 0; i < size; i++) {
      data[i] = pattern[i % patternSize];
    }
    return data;
  }

  /// 生成一个包含多个相同块的Block
  static Block generateBlockWithDuplicates(int blockCount, int blockSize) {
    final sharedData = generateSequentialData(blockSize);
    final List<Uint8List> blocks = List.generate(blockCount, (_) => sharedData);
    return Block(blocks);
  }
}

/// 打印基准测试结果表格
void printBenchmarkResultsTable(List<BenchmarkBase> benchmarks) {
  // 标题行
  print('| Benchmark | Score (μs) | Memory Usage (bytes) |');
  print('|-----------|------------|---------------------|');

  // 数据行
  for (final benchmark in benchmarks) {
    final score = benchmark.measure();
    final memoryUsage =
        benchmark is MemoryBenchmark ? '${benchmark.peakMemoryUsage}' : 'N/A';

    print('| ${benchmark.name} | ${score.toStringAsFixed(2)} | $memoryUsage |');
  }
}

/// 运行所有基准测试并生成报告
void runAllBenchmarks(List<BenchmarkBase> benchmarks) {
  for (final benchmark in benchmarks) {
    benchmark.report();
    print('-' * 50);
  }

  print('\n性能测试结果总表:');
  printBenchmarkResultsTable(benchmarks);
}
