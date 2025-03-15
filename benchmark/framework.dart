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
  /// 内存使用点记录
  final List<int> _memoryPoints = [];

  /// 保存当前测试的 Block 对象，防止垃圾回收
  final List<Block> _benchmarkBlocks = [];

  /// 创建内存基准测试
  MemoryBenchmark(super.name);

  @override
  void setup() {
    // 重置数据去重统计
    Block.resetDataDeduplication();

    // 记录初始内存使用量
    _memoryPoints.clear();
    _memoryPoints.add(Block.totalMemoryUsage);

    // 清空 Block 引用列表
    _benchmarkBlocks.clear();
  }

  /// 添加 Block 对象到引用列表，防止垃圾回收
  void addBlockReference(Block block) {
    _benchmarkBlocks.add(block);
  }

  /// 记录当前内存使用点
  void recordMemoryPoint() {
    _memoryPoints.add(Block.totalMemoryUsage);
  }

  @override
  void teardown() {
    // 强制更新内存统计
    Block.forceUpdateMemoryStatistics();

    // 确保在结束时记录内存点
    recordMemoryPoint();

    // 打印内存使用情况
    print('DEBUG: Memory Usage: ${Block.totalMemoryUsage} bytes');
    print('DEBUG: Active Blocks: ${Block.activeBlockCount}');
    print(
      'DEBUG: Peak Memory: ${_memoryPoints.isNotEmpty ? _memoryPoints.reduce((a, b) => a > b ? a : b) : 0} bytes',
    );
    print('DEBUG: Data Deduplication:');
    print(
      'DEBUG:   Duplicate Count: ${Block.getDataDeduplicationDuplicateCount()}',
    );
    print(
      'DEBUG:   Saved Memory: ${Block.getDataDeduplicationSavedMemory()} bytes',
    );

    // 清空 Block 引用，允许垃圾回收
    _benchmarkBlocks.clear();

    // 子类应在调用super.teardown()之前清理自己的资源
    super.teardown();
  }

  /// 获取内存使用情况
  int get memoryUsage {
    return _memoryPoints.isNotEmpty ? _memoryPoints.last : 0;
  }

  /// 获取最大内存使用量
  int get peakMemoryUsage {
    if (_memoryPoints.isEmpty) {
      return 0;
    }
    return _memoryPoints.reduce((a, b) => a > b ? a : b);
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
  print('');
  print(
    '| Benchmark | Score (μs) | Memory Usage (bytes) | Saved Memory (bytes) |',
  );
  print(
    '|-----------|------------|----------------------|----------------------|',
  );

  for (final benchmark in benchmarks) {
    final score = benchmark.measure();
    final memoryUsage =
        benchmark is MemoryBenchmark ? '${benchmark.peakMemoryUsage}' : 'N/A';
    final savedMemory =
        benchmark is MemoryBenchmark
            ? '${Block.getDataDeduplicationSavedMemory()}'
            : 'N/A';
    print(
      '| ${benchmark.name} | ${score.toStringAsFixed(2)} | $memoryUsage | $savedMemory |',
    );
  }
}

/// 运行所有基准测试
void runAllBenchmarks(List<BenchmarkBase> benchmarks) {
  print('=== 运行基准测试 ===');
  print('');

  // 设置内存使用限制，让系统更早地响应内存压力
  // 默认设置为256MB，可以根据实际情况调整
  Block.setMemoryUsageLimit(256 * 1024 * 1024);
  
  // 启动内存监控，每1秒检查一次内存使用情况
  final stopMonitor = Block.startMemoryMonitor(
    intervalMs: 1000,
    memoryLimit: 256 * 1024 * 1024,
  );
  
  // 订阅高内存压力通知
  final cancelHighPressure = Block.onMemoryPressureLevel(() {
    print('\n警告: 检测到高内存压力');
    print('当前内存使用: ${Block.totalMemoryUsage ~/ (1024 * 1024)}MB');
    print('正在自动清理内存...\n');
  }, level: MemoryPressureLevel.high);

  // 订阅危机内存压力通知
  final cancelCriticalPressure = Block.onMemoryPressureLevel(() {
    print('\n警告: 检测到危急内存压力！');
    print('当前内存使用: ${Block.totalMemoryUsage ~/ (1024 * 1024)}MB');
    print('进行紧急内存清理...\n');
    // 强制清理内存
    final freedBytes = Block.reduceMemoryUsage();
    print('已释放 ${freedBytes ~/ 1024}KB 内存\n');
  }, level: MemoryPressureLevel.critical);

  // 运行所有基准测试
  for (final benchmark in benchmarks) {
    benchmark.report();
  }

  // 运行完成后，打印基准测试结果表格
  printBenchmarkResultsTable(benchmarks);

  // 打印内存使用统计
  final memReport = Block.getGlobalMemoryReport();
  print('\n内存使用统计:');
  print('总内存使用: ${memReport['totalMemoryUsage'] ~/ 1024} KB');
  print('活跃Block数量: ${memReport['activeBlockCount']}');
  print('平均每个Block内存: ${memReport['averageBlockMemory'] ~/ 1024} KB');
  
  // 打印数据去重统计
  final dedupeReport = Block.getDataDeduplicationReport();
  print('\n数据去重统计:');
  print('唯一Block数量: ${dedupeReport['uniqueBlockCount']}');
  print('总字节数: ${dedupeReport['totalBytes'] ~/ 1024} KB');
  print('总引用计数: ${dedupeReport['totalRefCount']}');
  print('重复Block数量: ${dedupeReport['duplicateBlockCount']}');
  print('总节省内存: ${dedupeReport['totalSavedMemory'] ~/ 1024} KB');

  // 清理内存压力订阅和监控器
  cancelHighPressure();
  cancelCriticalPressure();
  stopMonitor();
  
  // 移除内存限制
  Block.setMemoryUsageLimit(null);
}
