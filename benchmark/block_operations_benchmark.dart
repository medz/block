// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:block/block.dart';
import 'framework.dart';

class BlockSliceBenchmark extends MemoryBenchmark {
  static const int _blockSize = 10 * 1024 * 1024; // 10MB
  Block? _block;

  BlockSliceBenchmark() : super('Block.slice() (10MB)');

  @override
  void setUp() {
    super.setUp();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
  }

  @override
  void run() {
    if (_block != null) {
      _block!.slice(0, _block!.size ~/ 2);
    }
  }
}

class BlockGetByteDataViewBenchmark extends MemoryBenchmark {
  static const int _blockSize = 10 * 1024 * 1024; // 10MB
  Block? _block;

  BlockGetByteDataViewBenchmark() : super('Block.getByteDataView() (10MB)');

  @override
  void setUp() {
    super.setUp();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
  }

  @override
  void run() {
    if (_block != null) {
      _block!.getByteDataView();
    }
  }
}

class BlockGetDirectDataBenchmark extends MemoryBenchmark {
  static const int _blockSize = 10 * 1024 * 1024; // 10MB
  Block? _block;

  BlockGetDirectDataBenchmark() : super('Block.getDirectData() (10MB)');

  @override
  void setUp() {
    super.setUp();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
  }

  @override
  void run() {
    if (_block != null) {
      _block!.getDirectData();
    }
  }
}

class BlockArrayBufferBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 5MB
  Block? _block;

  BlockArrayBufferBenchmark() : super('Block.arrayBuffer() (5MB)');

  @override
  void setUp() {
    super.setUp();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
  }

  @override
  void run() {
    if (_block != null) {
      _block!.arrayBuffer();
    }
  }
}

class BlockTextBenchmark extends MemoryBenchmark {
  static const int _charCount = 1 * 1024 * 1024; // 1M characters
  Block? _block;

  BlockTextBenchmark() : super('Block.text() (1MB)');

  @override
  void setUp() {
    super.setUp();
    final text = 'a' * _charCount;
    _block = Block([text]);
  }

  @override
  void run() {
    if (_block != null) {
      _block!.text;
    }
  }
}

class BlockStreamBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 5MB
  Block? _block;

  BlockStreamBenchmark() : super('Block.stream() (5MB)');

  @override
  void setUp() {
    super.setUp();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
  }

  @override
  void run() {
    if (_block != null) {
      _block!.stream;
    }
  }
}

class BlockDeferredOperationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 5MB
  Block? _block;

  BlockDeferredOperationBenchmark() : super('Block DeferredOperation (5MB)');

  @override
  void setUp() {
    super.setUp();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
  }

  @override
  void run() {
    if (_block != null) {
      final textOp = _block!.textOperation();
      final transformOp = _block!.transformOperation<int>(
        (data) => Future.value(data.length),
        'length',
      );
    }
  }
}

void main() {
  final benchmarks = <BenchmarkBase>[
    BlockSliceBenchmark(),
    BlockGetByteDataViewBenchmark(),
    BlockGetDirectDataBenchmark(),
    BlockArrayBufferBenchmark(),
    BlockTextBenchmark(),
    BlockStreamBenchmark(),
    BlockDeferredOperationBenchmark(),
  ];

  runAllBenchmarks(benchmarks);
}
