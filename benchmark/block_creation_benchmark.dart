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
  Block? _block;

  SmallBlockCreationBenchmark() : super('Small Block Creation (10KB)');

  @override
  void setup() {
    super.setup();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      _block = Block([_data!]);
      // 触发数据处理
      _block!.size;
      // 添加引用，防止垃圾回收
      addBlockReference(_block!);
    }
  }

  @override
  void teardown() {
    // 清理资源
    _block = null;
    _data = null;
    super.teardown();
  }
}

/// 中型Block创建测试
class MediumBlockCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 1 * 1024 * 1024; // 1MB
  Uint8List? _data;
  Block? _block;

  MediumBlockCreationBenchmark() : super('Medium Block Creation (1MB)');

  @override
  void setup() {
    super.setup();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      _block = Block([_data!]);
      // 触发数据处理
      _block!.size;
      // 添加引用，防止垃圾回收
      addBlockReference(_block!);
    }
  }

  @override
  void teardown() {
    // 清理资源
    _block = null;
    _data = null;
    super.teardown();
  }
}

/// 大型Block创建测试
class LargeBlockCreationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 10 * 1024 * 1024; // 10MB
  Uint8List? _data;
  Block? _block;

  LargeBlockCreationBenchmark() : super('Large Block Creation (10MB)');

  @override
  void setup() {
    super.setup();
    _data = TestDataGenerator.generateSequentialData(_blockSize);
  }

  @override
  void run() {
    if (_data != null) {
      _block = Block([_data!]);
      // 触发数据处理
      _block!.size;
      // 添加引用，防止垃圾回收
      addBlockReference(_block!);
    }
  }

  @override
  void teardown() {
    // 清理资源
    _block = null;
    _data = null;
    super.teardown();
  }
}

/// 多部分Block创建测试
class MultiPartBlockCreationBenchmark extends MemoryBenchmark {
  static const int _partCount = 5;
  static const int _partSize = 1 * 1024 * 1024; // 1MB
  List<Uint8List>? _parts;
  Block? _block;

  MultiPartBlockCreationBenchmark()
    : super('Multi-part Block Creation (5x 1MB)');

  @override
  void setup() {
    super.setup();
    _parts = List.generate(
      _partCount,
      (i) => TestDataGenerator.generateSequentialData(_partSize),
    );
  }

  @override
  void run() {
    if (_parts != null) {
      _block = Block(_parts!);
      // 触发数据处理
      _block!.size;
      // 添加引用，防止垃圾回收
      addBlockReference(_block!);
    }
  }

  @override
  void teardown() {
    // 清理资源
    _block = null;
    _parts?.clear();
    _parts = null;
    super.teardown();
  }
}

/// 字符串Block创建测试
class StringBlockCreationBenchmark extends MemoryBenchmark {
  static const int _charCount = 1000000; // 1M字符
  String? _text;
  Block? _block;

  StringBlockCreationBenchmark() : super('String Block Creation (1M chars)');

  @override
  void setup() {
    super.setup();
    // 创建一个包含100万字符的字符串
    final buffer = StringBuffer();
    for (int i = 0; i < _charCount; i++) {
      buffer.write(String.fromCharCode(65 + (i % 26))); // A-Z循环
    }
    _text = buffer.toString();
  }

  @override
  void run() {
    if (_text != null) {
      _block = Block([_text!]);
      // 触发数据处理
      _block!.size;
      // 添加引用，防止垃圾回收
      addBlockReference(_block!);
    }
  }

  @override
  void teardown() {
    // 清理资源
    _block = null;
    _text = null;
    super.teardown();
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
