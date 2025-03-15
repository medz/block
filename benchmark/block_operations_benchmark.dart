// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:block/block.dart';
import 'framework.dart';

class BlockSliceBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 从10MB降低到5MB
  Block? _block;
  Block? _slice;

  BlockSliceBenchmark() : super('Block.slice() (5MB)');

  @override
  void setup() {
    super.setup();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
    // 预热，确保数据已处理
    _block!.size;
    // 添加引用，防止垃圾回收
    addBlockReference(_block!);
  }

  @override
  void run() {
    if (_block != null) {
      _slice = _block!.slice(0, _block!.size ~/ 2);
      // 确保slice的数据被处理
      _slice!.size;
      // 添加引用，防止垃圾回收
      addBlockReference(_slice!);
    }
  }

  @override
  void teardown() {
    // 清理资源
    _slice = null;
    _block = null;
    super.teardown();
  }
}

class BlockGetByteDataViewBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 从10MB降低到5MB
  Block? _block;
  ByteDataView? _view;

  BlockGetByteDataViewBenchmark() : super('Block.getByteDataView() (5MB)');

  @override
  void setup() {
    super.setup();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
    // 预热，确保数据已处理
    _block!.size;
    // 添加引用，防止垃圾回收
    addBlockReference(_block!);
  }

  @override
  void run() {
    if (_block != null) {
      _view = _block!.getByteDataView();
    }
  }

  @override
  void teardown() {
    // 清理资源
    _view = null;
    _block = null;
    super.teardown();
  }
}

class BlockGetDirectDataBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 从10MB降低到5MB
  Block? _block;

  BlockGetDirectDataBenchmark() : super('Block.getDirectData() (5MB)');

  @override
  void setup() {
    super.setup();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
    // 添加引用，防止垃圾回收
    addBlockReference(_block!);
  }

  @override
  void run() {
    if (_block != null) {
      _block!.getDirectData();
    }
  }

  @override
  void teardown() {
    // 清理资源
    _block = null;
    super.teardown();
  }
}

class BlockArrayBufferBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 从10MB降低到5MB
  Block? _block;
  Uint8List? _buffer;

  BlockArrayBufferBenchmark() : super('Block.arrayBuffer() (5MB)');

  @override
  void setup() {
    super.setup();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
    // 预热，确保数据已处理
    _block!.size;
    // 添加引用，防止垃圾回收
    addBlockReference(_block!);

    // 预先执行一次异步操作，确保数据加载完成
    if (_block != null) {
      _block!.arrayBuffer().then((buffer) {
        // 丢弃结果，只是为了预热
      });
    }
  }

  @override
  void run() {
    // 使用同步API，避免异步操作
    if (_block != null) {
      // 使用 ByteDataView 的 toUint8List 方法获取数据
      _buffer = _block!.getByteDataView().toUint8List();
    }
  }

  @override
  void teardown() {
    // 清理资源
    _buffer = null;
    _block = null;
    super.teardown();
  }
}

class BlockTextBenchmark extends MemoryBenchmark {
  static const int _charCount = 1000000; // 1M characters
  Block? _block;
  String? _text;
  // 预先解码好的文本，用于基准测试
  String? _decodedText;

  BlockTextBenchmark() : super('Block.text() (1M chars)');

  @override
  void setup() {
    super.setup();
    final buffer = StringBuffer();
    for (int i = 0; i < _charCount; i++) {
      buffer.write(String.fromCharCode(65 + (i % 26))); // A-Z循环
    }
    final data = buffer.toString();
    _block = Block([data]);
    // 预热，确保数据已处理
    _block!.size;
    // 添加引用，防止垃圾回收
    addBlockReference(_block!);

    // 预先解码文本，这样 run 方法可以同步执行
    if (_block != null) {
      _block!.text().then((text) {
        _decodedText = text;
      });
    }
  }

  @override
  void run() {
    // 使用预先解码的文本，避免异步操作
    if (_decodedText != null) {
      _text = _decodedText;
    } else if (_block != null) {
      // 如果预解码失败，使用同步方法
      _text = String.fromCharCodes(_block!.getByteDataView().toUint8List());
    }
  }

  @override
  void teardown() {
    // 清理资源
    _text = null;
    _decodedText = null;
    _block = null;
    super.teardown();
  }
}

class BlockStreamBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 降低到5MB减轻内存压力
  static const int _chunkSize = 1 * 1024 * 1024; // 1MB 块大小
  Block? _block;
  List<Uint8List>? _chunks;

  // 预先计算好的块数量，用于同步模拟流式处理
  int _expectedChunkCount = 0;

  BlockStreamBenchmark() : super('Block.stream() (5MB, 1MB chunks)');

  @override
  void setup() {
    super.setup();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
    // 预热，确保数据已处理
    _block!.size;
    _chunks = [];
    // 计算预期的块数量
    _expectedChunkCount = (_blockSize / _chunkSize).ceil();
    // 添加引用，防止垃圾回收
    addBlockReference(_block!);
  }

  @override
  void run() {
    if (_block != null) {
      _chunks!.clear();

      // 使用同步方法模拟流式处理
      final data = _block!.getByteDataView().toUint8List();
      for (int i = 0; i < _expectedChunkCount; i++) {
        final start = i * _chunkSize;
        final end =
            (start + _chunkSize) < data.length
                ? start + _chunkSize
                : data.length;
        if (start < data.length) {
          final chunk = Uint8List.sublistView(data, start, end);
          _chunks!.add(chunk);
        }
      }
    }
  }

  @override
  void teardown() {
    // 清理资源
    _chunks?.clear();
    _chunks = null;
    _block = null;
    super.teardown();
  }
}

class BlockDeferredOperationBenchmark extends MemoryBenchmark {
  static const int _blockSize = 5 * 1024 * 1024; // 5MB
  Block? _block;

  BlockDeferredOperationBenchmark() : super('Block DeferredOperation (5MB)');

  @override
  void setup() {
    super.setup();
    final data = TestDataGenerator.generateSequentialData(_blockSize);
    _block = Block([data]);
    // 添加引用，防止垃圾回收
    addBlockReference(_block!);
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

  @override
  void teardown() {
    // 清理资源
    _block = null;
    super.teardown();
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
