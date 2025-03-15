// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:block/block.dart';
import 'framework.dart';

/// 小型Block创建测试
class SmallBlockCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 10 * 1024; // 10KB
  Uint8List? _data;

  SmallBlockCreationBenchmark() : super('Small Block Creation (10KB)');

  @override
  void setUp() {
    super.setUp();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      Block([_data!]);
    }
  }
}

/// 中型Block创建测试
class MediumBlockCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 1 * 1024 * 1024; // 1MB
  Uint8List? _data;

  MediumBlockCreationBenchmark() : super('Medium Block Creation (1MB)');

  @override
  void setUp() {
    super.setUp();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      Block([_data!]);
    }
  }
}

/// 大型Block创建测试
class LargeBlockCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 10 * 1024 * 1024; // 10MB
  Uint8List? _data;

  LargeBlockCreationBenchmark() : super('Large Block Creation (10MB)');

  @override
  void setUp() {
    super.setUp();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      Block([_data!]);
    }
  }
}

/// 多部分Block创建测试
class MultiPartBlockCreationBenchmark extends MemoryBenchmark {
  static const int _partSize = 1 * 1024 * 1024; // 1MB
  static const int _partCount = 5; // 5 parts, total 5MB
  List<Uint8List>? _parts;

  MultiPartBlockCreationBenchmark() : super('Multi-Part Block Creation (5MB)');

  @override
  void setUp() {
    super.setUp();
    _parts = List.generate(
      _partCount,
      (_) => TestDataGenerator.generateSequentialData(_partSize),
    );
  }

  @override
  void run() {
    if (_parts != null) {
      Block(_parts!);
    }
  }
}

/// 字符串Block创建测试
class StringBlockCreationBenchmark extends MemoryBenchmark {
  static const int _charCount = 1 * 1024 * 1024; // 1M characters
  String? _text;

  StringBlockCreationBenchmark() : super('String Block Creation (1M chars)');

  @override
  void setUp() {
    super.setUp();
    // 创建一个包含1M个字符的字符串
    _text = 'a' * _charCount;
  }

  @override
  void run() {
    if (_text != null) {
      Block([_text!]);
    }
  }
}

/// 主函数
void main() {
  final benchmarks = <BenchmarkBase>[
    SmallBlockCreationBenchmark(),
    MediumBlockCreationBenchmark(),
    LargeBlockCreationBenchmark(),
    MultiPartBlockCreationBenchmark(),
    StringBlockCreationBenchmark(),
  ];

  runAllBenchmarks(benchmarks);
}
