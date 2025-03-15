// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:block/block.dart';
import 'framework.dart';

class DuplicateDataCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 1 * 1024 * 1024; // 1MB
  static const int _blockCount = 10; // 创建10个相同的块
  Uint8List? _data;

  DuplicateDataCreationBenchmark()
    : super('Duplicate Block Creation (10x 1MB)');

  @override
  void setUp() {
    super.setUp();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      // 创建10个包含相同数据的Block
      for (int i = 0; i < _blockCount; i++) {
        Block([_data!]);
      }
    }

    // 记录内存使用情况
    recordMemoryPoint();
  }
}

class UniqueDataCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 1 * 1024 * 1024; // 1MB
  static const int _blockCount = 10; // 创建10个不同的块
  List<Uint8List>? _dataList;

  UniqueDataCreationBenchmark() : super('Unique Block Creation (10x 1MB)');

  @override
  void setUp() {
    super.setUp();
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
      // 创建10个包含不同数据的Block
      for (int i = 0; i < _blockCount; i++) {
        Block([_dataList![i]]);
      }
    }

    // 记录内存使用情况
    recordMemoryPoint();
  }
}

class DeduplicationMetricsBenchmark extends MemoryBenchmark {
  static const int _blockSize = 1 * 1024 * 1024; // 1MB
  static const int _blockCount = 20; // 创建20个块，其中10个相同
  Uint8List? _sharedData;
  List<Uint8List>? _uniqueDataList;

  DeduplicationMetricsBenchmark()
    : super('Deduplication Metrics (20x 1MB, 50% duplicates)');

  @override
  void setUp() {
    super.setUp();
    _sharedData = TestDataGenerator.generateSequentialData(_blockSize);
    _uniqueDataList = [];
    for (int i = 0; i < _blockCount / 2; i++) {
      final data = TestDataGenerator.generateSequentialData(_blockSize);
      data[0] = i + 100; // 确保数据不同
      _uniqueDataList!.add(data);
    }
  }

  @override
  void run() {
    if (_sharedData != null && _uniqueDataList != null) {
      // 创建10个使用共享数据的Block
      for (int i = 0; i < _blockCount / 2; i++) {
        Block([_sharedData!]);
      }

      // 创建10个使用不同数据的Block
      for (int i = 0; i < _blockCount / 2; i++) {
        Block([_uniqueDataList![i]]);
      }
    }

    // 记录最终指标
    recordMemoryPoint();
    final report = Block.getDataDeduplicationReport();
    print('Deduplication Report: $report');
    print('Saved Memory: ${Block.getDataDeduplicationSavedMemory()} bytes');
    print('Duplicate Count: ${Block.getDataDeduplicationDuplicateCount()}');
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
