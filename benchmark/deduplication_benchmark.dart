// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:block/block.dart';
import 'framework.dart';

class DuplicateDataCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 512 * 1024; // 从1MB降低到512KB
  static const int _blockCount = 10; // 创建10个相同的块
  Uint8List? _data;
  final List<Block> _blocks = [];

  DuplicateDataCreationBenchmark()
    : super('Duplicate Block Creation (10x 512KB)');

  @override
  void setup() {
    super.setup();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      _blocks.clear();
      // 创建10个包含相同数据的Block
      for (int i = 0; i < _blockCount; i++) {
        final block = Block([_data!]);
        // 触发数据处理
        block.size;
        _blocks.add(block);
        // 添加到引用列表，防止垃圾回收
        addBlockReference(block);
      }
    }

    // 强制更新内存统计
    Block.forceUpdateMemoryStatistics();

    // 记录内存使用情况
    recordMemoryPoint();

    // 打印数据去重统计
    print('Duplicate Count: ${Block.getDataDeduplicationDuplicateCount()}');
    print('Saved Memory: ${Block.getDataDeduplicationSavedMemory()} bytes');
  }

  @override
  void teardown() {
    // 清理资源
    _blocks.clear();
    _data = null;
    // 父类会清理引用，允许垃圾回收
    super.teardown();
  }
}

class UniqueDataCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 512 * 1024; // 从1MB降低到512KB
  static const int _blockCount = 10; // 创建10个不同的块
  List<Uint8List>? _dataList;
  final List<Block> _blocks = [];

  UniqueDataCreationBenchmark() : super('Unique Block Creation (10x 512KB)');

  @override
  void setup() {
    super.setup();
    _dataList = [];
    for (int i = 0; i < _blockCount; i++) {
      // 每个块都有稍微不同的数据
      final data = TestDataGenerator.generateSequentialData(_blockSize);
      data[0] = i; // 确保每个块都不同
      _dataList!.add(data);
    }
  }

  @override
  void run() {
    if (_dataList != null) {
      _blocks.clear();
      // 创建10个包含不同数据的Block
      for (int i = 0; i < _blockCount; i++) {
        final block = Block([_dataList![i]]);
        // 触发数据处理
        block.size;
        _blocks.add(block);
        // 添加到引用列表，防止垃圾回收
        addBlockReference(block);
      }
    }

    // 强制更新内存统计
    Block.forceUpdateMemoryStatistics();

    // 记录内存使用情况
    recordMemoryPoint();

    // 打印数据去重统计
    print('Duplicate Count: ${Block.getDataDeduplicationDuplicateCount()}');
    print('Saved Memory: ${Block.getDataDeduplicationSavedMemory()} bytes');
  }

  @override
  void teardown() {
    // 清理资源
    _blocks.clear();
    _dataList?.clear();
    _dataList = null;
    // 父类会清理引用，允许垃圾回收
    super.teardown();
  }
}

class DeduplicationMetricsBenchmark extends MemoryBenchmark {
  static const int _blockSize = 512 * 1024; // 从1MB降低到512KB
  static const int _duplicateCount = 5; // 多少个是重复的
  static const int _uniqueCount = 5; // 多少个是唯一的
  final List<Block> _blocks = [];

  Uint8List? _sharedData;
  List<Uint8List>? _uniqueDataList;

  DeduplicationMetricsBenchmark()
    : super(
        'Deduplication Metrics (5 unique + 5 duplicate blocks, 512KB each)',
      );

  @override
  void setup() {
    super.setup();
    // 生成共享数据和唯一数据
    _sharedData = TestDataGenerator.generateSequentialData(_blockSize);
    _uniqueDataList = [];

    // 创建唯一数据列表
    for (int i = 0; i < _uniqueCount; i++) {
      final data = TestDataGenerator.generateSequentialData(_blockSize);
      data[0] = i + 100; // 确保数据不同
      _uniqueDataList!.add(data);
    }
  }

  @override
  void run() {
    if (_sharedData != null && _uniqueDataList != null) {
      _blocks.clear();

      // 创建使用共享数据的 Block
      for (int i = 0; i < _duplicateCount; i++) {
        final block = Block([_sharedData!]);
        // 触发数据处理
        block.size;
        _blocks.add(block);
        // 添加到引用列表，防止垃圾回收
        addBlockReference(block);
      }

      // 创建使用不同数据的 Block
      for (int i = 0; i < _uniqueCount; i++) {
        final block = Block([_uniqueDataList![i]]);
        // 触发数据处理
        block.size;
        _blocks.add(block);
        // 添加到引用列表，防止垃圾回收
        addBlockReference(block);
      }
    }

    // 强制更新内存统计
    Block.forceUpdateMemoryStatistics();

    // 记录最终指标
    recordMemoryPoint();

    // 打印详细的去重报告
    print('Duplicate Count: ${Block.getDataDeduplicationDuplicateCount()}');
    final report = Block.getDataDeduplicationReport();
    print('Deduplication Report: $report');
    print('Saved Memory: ${Block.getDataDeduplicationSavedMemory()} bytes');
  }

  @override
  void teardown() {
    // 清理资源
    _blocks.clear();
    _sharedData = null;
    _uniqueDataList?.clear();
    _uniqueDataList = null;
    // 父类会清理引用，允许垃圾回收
    super.teardown();
  }
}

void main() {
  final benchmarks = <BenchmarkBase>[
    DuplicateDataCreationBenchmark(),
    UniqueDataCreationBenchmark(),
    DeduplicationMetricsBenchmark(),
  ];

  runAllBenchmarks(benchmarks);
}
