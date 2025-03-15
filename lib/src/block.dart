// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// 性能优化说明:
// 本实现参考了WebKit中Blob的实现，采用了多种策略避免不必要的数据复制:
// 1. 分片操作(slice)采用引用原始数据的方式，不复制数据，只保存引用和范围信息
// 2. 多层嵌套分片会被扁平化，避免链式引用导致的性能问题
// 3. 数据读取操作尽可能避免复制，使用sublist等方法直接引用原始数据
// 4. 流式读取针对分片进行了优化，只读取必要的数据段
// 5. 通过ByteDataView提供零拷贝数据访问机制，允许直接操作底层数据而不复制
// 6. 完整的零拷贝操作支持，包括视图转换和直接引用访问

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'block_cache.dart';
import 'block_memory_tracker.dart';
import 'byte_data_view.dart';
import 'cache_priority.dart';
import 'data_store.dart';
import 'deferred_operation.dart';
import 'memory_manager.dart';
import 'memory_pressure_level.dart';

/// A Block object represents an immutable, raw data file-like object.
///
/// This is a pure Dart implementation inspired by the Web API Blob.
/// It provides a way to handle binary data in Dart that works across all platforms.
class Block {
  /// The raw parts from which this Block was created
  final List<dynamic>? _rawParts;

  /// The list of data chunks that make up this Block
  final List<Uint8List> _chunks;

  /// The MIME type of this Block
  final String _type;

  /// The parent Block (if this is a slice)
  final Block? _parent;

  /// The start offset within the parent Block (if this is a slice)
  final int _startOffset;

  /// The length of this Block (or slice)
  late final int _sliceLength;

  /// The memory cost of this Block
  final int _memoryCost;

  /// Whether the data has been processed
  bool _dataProcessed;

  /// The data size in bytes.
  ///
  /// This is lazily calculated when first accessed and then cached.
  int? _size;

  /// 静态内存统计：跟踪所有Block实例的总内存使用量
  static int _totalMemoryUsage = 0;

  /// 静态内存统计：跟踪活跃Block实例数量
  static int _activeBlockCount = 0;

  /// 获取所有Block实例的当前总内存使用量（以字节为单位）
  static int get totalMemoryUsage => _totalMemoryUsage;

  /// 获取当前活跃的Block实例数量
  static int get activeBlockCount => _activeBlockCount;

  /// 获取当前Block实例的内存使用成本（以字节为单位）
  int get memoryCost => _memoryCost;

  /// 获取内存使用统计报告
  ///
  /// 返回一个Map，包含当前Block实例和整体内存使用情况的详细信息
  ///
  /// 示例:
  /// ```dart
  /// final report = block.getMemoryReport();
  /// print('Block size: ${report['size']} bytes');
  /// print('Memory usage: ${report['memoryCost']} bytes');
  /// ```
  Map<String, dynamic> getMemoryReport() {
    return {
      'size': size,
      'memoryCost': _memoryCost,
      'isSlice': _parent != null,
      'hasMultipleChunks': _chunks.length > 1,
      'chunksCount': _chunks.length,
    };
  }

  /// 获取全局内存使用统计报告
  ///
  /// 返回一个Map，包含所有Block实例的内存使用情况
  ///
  /// 示例:
  /// ```dart
  /// final report = Block.getGlobalMemoryReport();
  /// print('Total memory usage: ${report['totalMemoryUsage']} bytes');
  /// print('Active blocks: ${report['activeBlockCount']}');
  /// ```
  static Map<String, dynamic> getGlobalMemoryReport() {
    return {
      'totalMemoryUsage': _totalMemoryUsage,
      'activeBlockCount': _activeBlockCount,
      'averageBlockSize':
          _activeBlockCount > 0 ? _totalMemoryUsage / _activeBlockCount : 0,
    };
  }

  /// 当前内存压力级别
  static MemoryPressureLevel _currentPressureLevel = MemoryPressureLevel.none;

  /// 内存使用限制 (字节)
  static int? _memoryUsageLimit;

  /// 内存压力回调列表
  static final Map<MemoryPressureLevel, List<void Function()>>
  _pressureCallbacks = {
    MemoryPressureLevel.none: [],
    MemoryPressureLevel.low: [],
    MemoryPressureLevel.medium: [],
    MemoryPressureLevel.high: [],
    MemoryPressureLevel.critical: [],
  };

  /// 获取当前内存压力级别
  static MemoryPressureLevel get currentMemoryPressureLevel =>
      _currentPressureLevel;

  /// 设置内存使用上限
  ///
  /// 当内存使用超过此限制时，会自动触发高内存压力事件。
  /// 设置为null表示无限制。
  ///
  /// 示例:
  /// ```dart
  /// // 设置100MB的内存使用上限
  /// Block.setMemoryUsageLimit(100 * 1024 * 1024);
  ///
  /// // 移除限制
  /// Block.setMemoryUsageLimit(null);
  /// ```
  static void setMemoryUsageLimit(int? limitBytes) {
    _memoryUsageLimit = limitBytes;
    _checkMemoryPressure();
  }

  /// 获取当前设置的内存使用上限
  static int? get memoryUsageLimit => _memoryUsageLimit;

  /// 注册一个在指定内存压力级别下执行的回调
  ///
  /// 这允许应用程序在不同的内存压力级别上采取不同的措施。
  ///
  /// 参数:
  /// - callback: 在达到指定内存压力级别时调用的函数
  /// - level: 触发回调的内存压力级别
  ///
  /// 返回一个用于取消订阅的函数
  ///
  /// 示例:
  /// ```dart
  /// final cancel = Block.onMemoryPressureLevel(() {
  ///   // 执行高压力下的内存清理
  ///   print('High memory pressure detected!');
  /// }, level: MemoryPressureLevel.high);
  ///
  /// // 稍后取消订阅
  /// cancel();
  /// ```
  static Function onMemoryPressureLevel(
    void Function() callback, {
    required MemoryPressureLevel level,
  }) {
    _pressureCallbacks[level]!.add(callback);

    return () {
      _pressureCallbacks[level]!.remove(callback);
    };
  }

  /// 手动触发指定级别的内存压力事件
  ///
  /// 这通常用于测试内存压力处理机制，或者在外部系统检测到内存压力时手动触发。
  ///
  /// 参数:
  /// - level: 要触发的内存压力级别
  ///
  /// 示例:
  /// ```dart
  /// // 模拟高内存压力
  /// Block.triggerMemoryPressure(MemoryPressureLevel.high);
  /// ```
  static void triggerMemoryPressure(MemoryPressureLevel level) {
    _currentPressureLevel = level;
    _notifyMemoryPressureCallbacks(level);

    // 自动响应内存压力
    _autoReduceMemoryUsage(level);
  }

  /// 释放可能的缓存内存，降低内存使用
  ///
  /// 此方法尝试释放不必要的内部缓存以减少内存使用。
  /// 实际释放的内存量取决于当前的使用情况和可释放的缓存量。
  ///
  /// 返回释放的字节数（估计值）。
  ///
  /// 示例:
  /// ```dart
  /// int freedBytes = Block.reduceMemoryUsage();
  /// print('释放了 $freedBytes 字节的内存');
  /// ```
  static int reduceMemoryUsage() {
    // 清理缓存和未引用的共享数据
    int freedBytes = 0;

    // 清理缓存
    freedBytes += BlockCache.instance.clearByPressureLevel(
      MemoryPressureLevel.medium,
    );

    // 清理未引用的共享数据
    freedBytes += DataStore.instance.reduceMemoryUsage();

    return freedBytes;
  }

  /// 根据内存压力级别自动释放内存
  static int _autoReduceMemoryUsage(MemoryPressureLevel level) {
    int freedBytes = 0;

    switch (level) {
      case MemoryPressureLevel.low:
        // 轻度压力：清理非关键缓存
        freedBytes = BlockCache.instance.clearByPressureLevel(level);
        // 增加当轻度压力下的缓存和未使用数据的清理频率
        freedBytes += DataStore.instance.cleanUnreferencedData();
        break;
      case MemoryPressureLevel.medium:
        // 中度压力：清理所有缓存
        freedBytes = BlockCache.instance.clearByPressureLevel(level);
        // 清理未引用的共享数据
        freedBytes += DataStore.instance.reduceMemoryUsage();
        break;
      case MemoryPressureLevel.high:
      case MemoryPressureLevel.critical:
        // 高压力：清理所有缓存并强制释放所有可能的内存
        freedBytes = BlockCache.instance.clearByPressureLevel(level);
        freedBytes += reduceMemoryUsage();

        // 在高压力或危急情况下，主动触发垃圾回收
        if (level == MemoryPressureLevel.critical) {
          // 使用间接方式提示垃圾回收器工作
          _suggestGarbageCollection();
        }
        break;
      case MemoryPressureLevel.none:
        // 无压力：只清理过期缓存和未引用的数据
        freedBytes = BlockCache.instance.clearByPressureLevel(level);
        // 清理未引用的共享数据
        freedBytes += DataStore.instance.cleanUnreferencedData();
        break;
    }

    return freedBytes;
  }

  // 提示垃圾回收器工作的辅助方法
  static void _suggestGarbageCollection() {
    List<int>? largeList = List<int>.filled(1024 * 1024, 0); // 分配1MB临时内存
    largeList = null; // 立即释放引用
  }

  /// 检查内存压力状态并更新压力级别
  static void _checkMemoryPressure() {
    MemoryPressureLevel newLevel;

    // 根据当前内存使用情况和限制确定压力级别
    if (_memoryUsageLimit == null) {
      newLevel = MemoryPressureLevel.none;
    } else {
      final double usageRatio = _totalMemoryUsage / _memoryUsageLimit!;

      // 降低阈值，让系统更早响应内存压力
      if (usageRatio >= 0.90) {
        // 从0.95降低到0.90
        newLevel = MemoryPressureLevel.critical;
      } else if (usageRatio >= 0.80) {
        // 从0.85降低到0.80
        newLevel = MemoryPressureLevel.high;
      } else if (usageRatio >= 0.65) {
        // 从0.7降低到0.65
        newLevel = MemoryPressureLevel.medium;
      } else if (usageRatio >= 0.45) {
        // 从0.5降低到0.45
        newLevel = MemoryPressureLevel.low;
      } else {
        newLevel = MemoryPressureLevel.none;
      }
    }

    // 如果压力级别发生变化，通知回调
    if (newLevel != _currentPressureLevel) {
      _currentPressureLevel = newLevel;
      _notifyMemoryPressureCallbacks(newLevel);

      // 自动响应内存压力
      _autoReduceMemoryUsage(newLevel);
    } else if (newLevel != MemoryPressureLevel.none) {
      // 即使压力级别没变，只要不是无压力状态，也定期执行内存释放
      // 避免在高内存使用时长时间不释放内存
      _autoReduceMemoryUsage(newLevel);
    }
  }

  /// 通知特定级别及更高级别的内存压力回调
  static void _notifyMemoryPressureCallbacks(MemoryPressureLevel level) {
    // 调用特定级别的回调
    for (final callback in _pressureCallbacks[level]!) {
      callback();
    }

    // 对于高压力级别，也通知更低级别的回调
    // 例如，高压力应该同时触发中压力和低压力的回调
    if (level == MemoryPressureLevel.critical) {
      _notifyMemoryPressureCallbacks(MemoryPressureLevel.high);
    } else if (level == MemoryPressureLevel.high) {
      _notifyMemoryPressureCallbacks(MemoryPressureLevel.medium);
    } else if (level == MemoryPressureLevel.medium) {
      _notifyMemoryPressureCallbacks(MemoryPressureLevel.low);
    }
  }

  /// 注册一个在需要减少内存使用时执行的回调
  ///
  /// 这是一个静态API，允许应用程序在内存压力大时得到通知并采取行动。
  /// 当内存使用量达到指定的阈值时，回调函数将被调用。
  ///
  /// 参数:
  /// - callback: 在内存压力超过阈值时调用的函数
  /// - thresholdBytes: 触发回调的内存使用阈值（字节）
  ///
  /// 返回一个用于取消订阅的函数
  ///
  /// 示例:
  /// ```dart
  /// final cancel = Block.onMemoryPressure(() {
  ///   // 执行内存清理操作
  ///   print('Memory pressure detected!');
  /// }, thresholdBytes: 100 * 1024 * 1024);
  ///
  /// // 稍后取消订阅
  /// cancel();
  /// ```
  static Function onMemoryPressure(
    void Function() callback, {
    required int thresholdBytes,
  }) {
    final periodicTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_totalMemoryUsage > thresholdBytes) {
        callback();
      }

      // 每次检查后更新内存压力状态
      _checkMemoryPressure();
    });

    return () => periodicTimer.cancel();
  }

  /// The default chunk size for segmented storage (reduced from 1MB to 512KB)
  static const int defaultChunkSize = 512 * 1024;

  /// 用于finalizer的回调函数
  static final _finalizer = Finalizer<BlockMemoryTracker>((tracker) {
    // 当Block被垃圾回收时，减少总内存使用量统计
    _totalMemoryUsage -= tracker.memoryCost;
    _activeBlockCount--;

    // 释放数据块引用
    for (final data in tracker.dataToRelease) {
      DataStore.instance.release(data);
    }
  });

  /// 生成唯一的Block ID
  static String _generateBlockId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(DateTime.now()) & 0xFFFFFF}';
  }

  /// 注册Block到内存管理器
  void _registerWithMemoryManager() {
    MemoryManager.instance.registerBlock(this, hashCode.toString());
  }

  /// 当处理数据时，将数据与此Block关联
  void _associateDataWithBlock(String dataId, int dataSize) {
    MemoryManager.instance.associateDataWithBlock(
      hashCode.toString(),
      dataId,
      dataSize,
    );
  }

  /// 当不再需要数据时，解除数据与此Block的关联
  void _dissociateDataFromBlock(String dataId, int dataSize) {
    MemoryManager.instance.dissociateDataFromBlock(
      hashCode.toString(),
      dataId,
      dataSize,
    );
  }

  /// 记录Block被访问
  void _recordBlockAccess() {
    MemoryManager.instance.recordBlockAccess(hashCode.toString());
  }

  /// Creates a new Block consisting of an optional array of parts and a MIME type.
  ///
  /// This constructor exactly mirrors the Web API Blob constructor.
  ///
  /// The parts parameter can include:
  /// - String
  /// - Uint8List
  /// - ByteData
  /// - Block objects
  ///
  /// The type parameter specifies the MIME type of the Block.
  ///
  /// Example:
  /// ```dart
  /// // Create a Block from multiple parts
  /// final block = Block([
  ///   'Hello, ',
  ///   Uint8List.fromList(utf8.encode('world')),
  ///   '!'
  /// ], type: 'text/plain');
  ///
  /// // Create an empty Block
  /// final emptyBlock = Block([], type: 'application/octet-stream');
  /// ```
  Block(List<dynamic> parts, {String type = ''})
    : _chunks = [], // 初始化为空列表，稍后再处理
      _rawParts = parts, // 保存原始参数
      _type = type,
      _parent = null,
      _startOffset = 0,
      _sliceLength = 0, // 稍后计算
      _memoryCost = _calculateMemoryCost(parts),
      _dataProcessed = false {
    // 验证每个part的类型
    for (final part in parts) {
      if (!(part is String ||
          part is Uint8List ||
          part is ByteData ||
          part is Block)) {
        throw ArgumentError(
          'Unsupported part type: ${part?.runtimeType}. '
          'Supported types are String, Uint8List, ByteData, and Block.',
        );
      }
    }
    _registerMemoryUsage();
    // 注册到内存管理器
    _registerWithMemoryManager();
  }

  /// Internal constructor for creating Block slices
  Block._slice(
    this._parent,
    this._startOffset,
    this._sliceLength, {
    required String type,
  }) : _chunks = [],
       _rawParts = null,
       _type = type,
       _memoryCost = _calculateSliceMemoryCost(_sliceLength),
       _dataProcessed = true {
    _registerMemoryUsage();
    // 注册到内存管理器
    _registerWithMemoryManager();
  }

  /// Internal constructor for creating Block from explicit chunks
  Block._fromChunks(this._chunks, int totalSize, this._type)
    : _parent = null,
      _rawParts = null,
      _startOffset = 0,
      _sliceLength = totalSize,
      _memoryCost = _calculateChunksMemoryCost(_chunks),
      _dataProcessed = true {
    _registerMemoryUsage();
    // 注册到内存管理器
    _registerWithMemoryManager();
  }

  /// 当需要时处理数据
  void _processDataIfNeeded() {
    // 如果已经处理过数据或没有原始数据，则直接返回
    if (_dataProcessed || _rawParts == null) {
      return;
    }

    // 处理原始数据
    final procesedChunks = _createBlockChunks(_rawParts);
    _chunks.addAll(procesedChunks);
    _sliceLength = _calculateTotalSize(_rawParts);

    // 标记为已处理
    _dataProcessed = true;
  }

  // 注册内存使用并设置finalizer
  void _registerMemoryUsage() {
    // 更新全局内存统计
    _totalMemoryUsage += _memoryCost;
    _activeBlockCount++;

    // 收集需要跟踪的数据块
    final dataToRelease = <Uint8List>[];

    // 只跟踪直接持有的数据块，slice不需要跟踪
    if (_parent == null && _chunks.isNotEmpty) {
      dataToRelease.addAll(_chunks);
    }

    // 注册finalizer以在GC时减少内存统计和释放数据
    _finalizer.attach(
      this,
      BlockMemoryTracker(_memoryCost, dataToRelease),
      detach: this,
    );

    // 每次创建新Block都检查内存压力状态
    _checkMemoryPressure();
  }

  /// 计算所有部分的总内存成本（包括元数据开销）
  static int _calculateMemoryCost(List<dynamic> parts) {
    if (parts.isEmpty) {
      return _blockInstanceBaseSize;
    }

    // 为了支持延迟加载，这里提供一个简单估计而不是实际处理数据
    // 这种估计可能不太准确，但能快速计算出大致的内存成本
    int memoryCost = _blockInstanceBaseSize;
    for (final part in parts) {
      if (part is String) {
        // 字符串的UTF-8编码后估计大小
        memoryCost += part.length * 2; // 粗略估计字符串的UTF-8大小
      } else if (part is Uint8List) {
        memoryCost += part.length;
      } else if (part is ByteData) {
        memoryCost += part.lengthInBytes;
      } else if (part is Block) {
        // 对于Block部分，使用它的memoryCost属性
        memoryCost += part.memoryCost;
      }
    }
    return memoryCost;
  }

  /// 计算切片的内存成本
  static int _calculateSliceMemoryCost(int sliceLength) {
    // 切片的内存成本包括基本的Block实例大小和对父Block的引用
    return _blockInstanceBaseSize + _blockReferenceSize;
  }

  /// 计算chunks的内存成本
  static int _calculateChunksMemoryCost(List<Uint8List> chunks) {
    int memoryCost = _blockInstanceBaseSize;
    for (final chunk in chunks) {
      memoryCost += chunk.length;
    }
    return memoryCost;
  }

  // Block实例的基本大小（估计值，包含实例字段和内部元数据）
  // 在Dart中实际内存使用很难精确计算，这是一个估计值
  static const int _blockInstanceBaseSize = 120;

  // Block引用的内存成本（估计值）
  static const int _blockReferenceSize = 8;

  /// Calculate the total size of all parts
  static int _calculateTotalSize(List<dynamic> parts) {
    if (parts.isEmpty) {
      return 0;
    }

    int totalSize = 0;
    for (final part in parts) {
      final Uint8List bytes = _convertPartToBytes(part);
      totalSize += bytes.length;
    }
    return totalSize;
  }

  /// Internal static method to create storage chunks from parts
  static List<Uint8List> _createBlockChunks(List<dynamic> parts) {
    if (parts.isEmpty) {
      return [];
    }

    final List<Uint8List> allBytes = [];
    for (final part in parts) {
      final Uint8List bytes = _convertPartToBytes(part);
      // 使用 DataStore.store 方法存储数据，以便跟踪数据去重
      final storedBytes = DataStore.instance.store(bytes);
      allBytes.add(storedBytes);
    }

    // Optimize for small data (< 1MB) by keeping it as a single chunk
    final int totalSize = allBytes.fold(0, (sum, bytes) => sum + bytes.length);
    if (totalSize <= defaultChunkSize && allBytes.length == 1) {
      return allBytes;
    }

    // For larger data or multiple parts, use segmented storage
    return _segmentDataIntoChunks(allBytes, totalSize);
  }

  /// Segment data into optimal chunks
  static List<Uint8List> _segmentDataIntoChunks(
    List<Uint8List> allBytes,
    int totalSize,
  ) {
    // If all parts are already small enough, just use them directly
    if (allBytes.every((bytes) => bytes.length <= defaultChunkSize)) {
      return List<Uint8List>.from(allBytes);
    }

    // Otherwise, reorganize into optimal chunk sizes
    final List<Uint8List> chunks = [];

    // First, handle very large individual parts by splitting them
    final List<Uint8List> normalizedParts = [];
    for (final bytes in allBytes) {
      if (bytes.length > defaultChunkSize) {
        // Split large parts into chunks
        int offset = 0;
        while (offset < bytes.length) {
          final int chunkSize =
              (offset + defaultChunkSize > bytes.length)
                  ? bytes.length - offset
                  : defaultChunkSize;

          final chunk = Uint8List(chunkSize);
          chunk.setRange(0, chunkSize, bytes, offset);
          normalizedParts.add(DataStore.instance.store(chunk));
          offset += chunkSize;
        }
      } else {
        normalizedParts.add(bytes);
      }
    }

    // Then optimize storage by combining small parts
    Uint8List? currentChunk;
    int currentSize = 0;

    for (final bytes in normalizedParts) {
      // If adding this part would exceed the chunk size, finalize current chunk
      if (currentChunk != null &&
          currentSize + bytes.length > defaultChunkSize) {
        chunks.add(currentChunk);
        currentChunk = null;
        currentSize = 0;
      }

      // Start a new chunk if needed
      if (currentChunk == null) {
        // If this part is exactly at chunk size, add it directly
        if (bytes.length == defaultChunkSize) {
          chunks.add(bytes);
          continue;
        }

        // Otherwise start a new chunk
        currentChunk = Uint8List(defaultChunkSize);
        currentSize = 0;
      }

      // Add bytes to the current chunk
      currentChunk.setRange(currentSize, currentSize + bytes.length, bytes);
      currentSize += bytes.length;

      // If chunk is full, finalize it
      if (currentSize == defaultChunkSize) {
        chunks.add(DataStore.instance.store(currentChunk));
        currentChunk = null;
        currentSize = 0;
      }
    }

    // Add any remaining data
    if (currentChunk != null && currentSize > 0) {
      // Create right-sized final chunk
      final finalChunk = Uint8List(currentSize);
      finalChunk.setRange(0, currentSize, currentChunk, 0);
      chunks.add(DataStore.instance.store(finalChunk));
    }

    return chunks;
  }

  /// Helper function to convert various types to Uint8List
  static Uint8List _convertPartToBytes(dynamic part) {
    Uint8List rawData;

    if (part is String) {
      rawData = Uint8List.fromList(utf8.encode(part));
    } else if (part is Uint8List) {
      rawData = part;
    } else if (part is ByteData) {
      rawData = Uint8List.view(
        part.buffer,
        part.offsetInBytes,
        part.lengthInBytes,
      );
    } else if (part is Block) {
      // 确保嵌套Block的数据已被处理
      part._processDataIfNeeded();

      // If it's already a Block, get its data
      // For a direct Block, we need to combine chunks
      if (part._parent == null && part._chunks.isNotEmpty) {
        if (part._chunks.length == 1) {
          rawData = part._chunks[0];
        } else {
          rawData = part._combineChunks();
        }
      }
      // For a slice, we need to get the slice data
      else if (part._parent != null) {
        final parentData = part._parent._combineChunks();
        final sliceData = Uint8List(part._sliceLength);
        sliceData.setRange(0, part._sliceLength, parentData, part._startOffset);
        rawData = sliceData;
      } else {
        // Empty Block
        rawData = Uint8List(0);
      }
    } else {
      throw ArgumentError(
        'Unsupported part type: ${part.runtimeType}. '
        'Supported types are String, Uint8List, ByteData, and Block.',
      );
    }

    // 使用数据去重存储
    return DataStore.instance.store(rawData);
  }

  /// Combines all chunks into a single Uint8List
  Uint8List _combineChunks() {
    // 尝试零拷贝访问
    final directData = getDirectData();
    if (directData != null) {
      return directData;
    }

    // 使用ByteDataView处理
    return getByteDataView().toUint8List();
  }

  /// Returns the size of the Block in bytes.
  ///
  /// This property corresponds to the Web API Blob.size property.
  int get size {
    _processDataIfNeeded();

    // 记录Block访问
    MemoryManager.instance.recordBlockAccess(hashCode.toString());

    if (_size != null) {
      return _size!;
    }

    if (_parent != null) {
      _size = _sliceLength;
    } else {
      _size = _calculateChunksSize(_chunks);
    }

    return _size!;
  }

  /// Returns the MIME type of the Block.
  String get type => _type;

  /// Returns a new Block object containing the data in the specified range.
  ///
  /// This method exactly mirrors the Web API Blob.slice() method.
  ///
  /// [start] - An index indicating the first byte to include in the new Block.
  /// [end] - An index indicating the first byte that will not be included in the new Block.
  /// [contentType] - The content type of the new Block, or an empty string if not specified.
  ///
  /// Example:
  /// ```dart
  /// final slice = block.slice(10, 20, 'text/plain');
  /// ```
  Block slice(int start, [int? end, String? contentType]) {
    // 确保数据已处理
    _processDataIfNeeded();

    // Handle negative indices
    final int dataSize = size;

    if (start < 0) start = dataSize + start;
    final int normalizedEnd =
        (end != null && end < 0) ? dataSize + end : (end ?? dataSize);

    // Clamp to valid range
    start = start.clamp(0, dataSize);
    final int endOffset = normalizedEnd.clamp(0, dataSize);

    if (start >= endOffset) {
      return Block([], type: contentType ?? _type);
    }

    final sliceLength = endOffset - start;

    // 优化: 避免过深的slice嵌套
    // 如果这已经是一个slice，寻找根Block以避免多层slice嵌套
    if (_parent != null) {
      // 找到根Block
      Block rootParent = _parent;
      int totalOffset = _startOffset + start;

      while (rootParent._parent != null) {
        totalOffset += rootParent._startOffset;
        rootParent = rootParent._parent;
      }

      // 从根Block创建slice，避免多层嵌套
      return Block._slice(
        rootParent,
        totalOffset,
        sliceLength,
        type: contentType ?? _type,
      );
    }

    // Otherwise create a slice of this Block
    return Block._slice(this, start, sliceLength, type: contentType ?? _type);
  }

  /// Returns a Promise that resolves with the contents of the Block as an ArrayBuffer.
  ///
  /// This method corresponds to the Web API Blob.arrayBuffer() method.
  ///
  /// Example:
  /// ```dart
  /// final data = await block.arrayBuffer();
  /// ```
  Future<Uint8List> arrayBuffer() async {
    // 确保数据已处理
    _processDataIfNeeded();

    // 尝试零拷贝方式获取数据
    final directData = getDirectData();
    if (directData != null) {
      // 可以直接引用，无需复制
      return Future.value(directData);
    }

    // 否则回退到使用ByteDataView
    return Future.value(getByteDataView().toUint8List());
  }

  /// Returns a Promise that resolves with a string containing the entire contents of the Block.
  ///
  /// This method corresponds to the Web API Blob.text() method.
  ///
  /// Example:
  /// ```dart
  /// final text = await block.text();
  /// ```
  Future<String> text({Encoding encoding = utf8}) async {
    // 返回延迟文本操作，节省了不需要立即执行时的解码成本
    return DeferredOperations.text(this, encoding: encoding).execute();
  }

  /// 创建延迟文本解码操作
  ///
  /// 返回一个可以在需要时执行的延迟操作，而不是立即执行解码。
  /// 这允许你使用链式操作而不必立即执行。
  ///
  /// 示例：
  /// ```dart
  /// final textOp = block.textOperation();
  /// // ... 执行其他操作 ...
  /// final text = await textOp.execute(); // 解码仅在这里执行
  /// ```
  DeferredOperation<String> textOperation({Encoding encoding = utf8}) {
    return DeferredOperations.text(this, encoding: encoding);
  }

  /// 静态方法合并多个Block
  ///
  /// 此方法创建一个新的Block，包含所有输入Block的数据。
  /// 这类似于将多个块连接在一起。
  ///
  /// 示例：
  /// ```dart
  /// final mergedBlock = await Block.merge([block1, block2, block3]);
  /// ```
  static Future<Block> merge(List<Block> blocks, {String type = ''}) async {
    return DeferredOperations.merge(blocks, type: type).execute();
  }

  /// 创建一个延迟合并操作
  ///
  /// 返回一个可以在需要时执行的延迟操作，而不是立即执行合并。
  ///
  /// 示例：
  /// ```dart
  /// final mergeOp = Block.mergeOperation([block1, block2, block3]);
  /// // ... 执行其他操作 ...
  /// final mergedBlock = await mergeOp.execute(); // 合并仅在这里执行
  /// ```
  static DeferredOperation<Block> mergeOperation(
    List<Block> blocks, {
    String type = '',
  }) {
    return DeferredOperations.merge(blocks, type: type);
  }

  /// 执行自定义数据转换操作
  ///
  /// 允许对Block数据应用自定义转换，并返回结果。
  /// 转换延迟执行直到需要结果。
  ///
  /// 示例：
  /// ```dart
  /// // 转换为base64字符串
  /// final base64 = await block.transform((data) =>
  ///   Future.value(base64Encode(data)),
  ///   'base64Encoding'
  /// );
  /// ```
  Future<T> transform<T>(
    Future<T> Function(Uint8List data) transformer,
    String transformType,
  ) async {
    return DeferredOperations.transform(
      this,
      transformer,
      transformType,
    ).execute();
  }

  /// 创建延迟数据转换操作
  ///
  /// 返回一个可以在需要时执行的延迟操作，而不是立即执行转换。
  ///
  /// 示例：
  /// ```dart
  /// final base64Op = block.transformOperation(
  ///   (data) => Future.value(base64Encode(data)),
  ///   'base64Encoding'
  /// );
  /// // ... 执行其他操作 ...
  /// final base64 = await base64Op.execute(); // 转换仅在这里执行
  /// ```
  DeferredOperation<T> transformOperation<T>(
    Future<T> Function(Uint8List data) transformer,
    String transformType,
  ) {
    return DeferredOperations.transform<T>(this, transformer, transformType);
  }

  /// 返回一个ByteDataView，允许在不复制的情况下访问数据
  ///
  /// 这是一个同步操作，提供对底层数据的直接视图，而不会复制数据。
  /// 如果不需要实际复制数据，这比arrayBuffer()更高效。
  ///
  /// 注意：返回的视图是只读的，修改视图不会影响原始Block数据。
  ///
  /// 示例:
  /// ```dart
  /// final view = block.getByteDataView();
  /// final byte = view.getUint8(10); // 获取第11个字节
  /// ```
  ByteDataView getByteDataView() {
    // 确保数据已处理
    _processDataIfNeeded();

    if (_parent != null) {
      // 从父Block创建视图
      var parentView = _parent.getByteDataView();
      return parentView.subView(_startOffset, _startOffset + _sliceLength);
    }

    return ByteDataView(_chunks, size);
  }

  /// 尝试获取底层数据的直接引用，而不需要复制数据
  ///
  /// 只有在Block只包含单个连续数据块时才会返回非null值。
  /// 这是最高效的访问方式，完全避免了数据复制。
  ///
  /// 返回null表示不能直接访问（数据是分段的或者是分片），
  /// 在这种情况下，应该使用arrayBuffer()或getByteDataView()。
  ///
  /// 示例:
  /// ```dart
  /// final directData = block.getDirectData();
  /// if (directData != null) {
  ///   // 直接使用数据，无需复制
  /// } else {
  ///   // 回退到复制方式
  ///   final data = await block.arrayBuffer();
  /// }
  /// ```
  Uint8List? getDirectData() {
    _processDataIfNeeded();

    // 记录Block访问
    MemoryManager.instance.recordBlockAccess(hashCode.toString());

    if (_parent != null) {
      return _parent.getDirectData()?.sublist(
        _startOffset,
        _startOffset + _sliceLength,
      );
    }

    if (_chunks.length == 1) {
      return _chunks[0];
    }

    return null;
  }

  /// 获取一个只读的ByteBuffer，尽可能避免数据复制
  ///
  /// 此方法会尝试直接返回底层数据的ByteBuffer，如果不可能则会创建一个新的。
  /// 比arrayBuffer()更高效，因为它会尝试避免不必要的数据复制。
  ///
  /// 示例:
  /// ```dart
  /// final buffer = block.getByteBuffer();
  /// // 使用buffer进行高效操作
  /// ```
  ByteBuffer getByteBuffer() {
    // 确保数据已处理
    _processDataIfNeeded();

    // 尝试获取直接数据引用
    final directData = getDirectData();
    if (directData != null) {
      return directData.buffer;
    }

    // 如果无法直接引用，创建视图并转换
    return getByteDataView().buffer;
  }

  /// Streams the Block's data in chunks.
  ///
  /// This is a Dart-specific addition that doesn't exist in the Web API Blob,
  /// but is useful for handling large data efficiently.
  ///
  /// The [chunkSize] parameter controls the size of each chunk.
  ///
  /// Example:
  /// ```dart
  /// await for (final chunk in block.stream(chunkSize: 1024)) {
  ///   // Process chunk
  /// }
  /// ```
  Stream<Uint8List> stream({int chunkSize = 1024 * 64}) async* {
    // 确保数据已处理
    _processDataIfNeeded();

    // 如果Block很小，直接返回整个数据
    if (size <= chunkSize) {
      // 尝试零拷贝方式获取数据
      final directData = getDirectData();
      if (directData != null) {
        yield directData;
        return;
      }

      // 否则使用ByteDataView
      yield getByteDataView().toUint8List();
      return;
    }

    // 对于分片数据，优化流式读取
    if (_parent != null) {
      // 当父Block是嵌套slice时，处理优化
      if (_parent._parent != null) {
        // 创建一个新的合并计算的slice直接从顶层读取
        final combinedSlice = _parent.slice(
          _startOffset,
          _startOffset + _sliceLength,
        );
        await for (final chunk in combinedSlice.stream(chunkSize: chunkSize)) {
          yield chunk;
        }
        return;
      }

      // 获取父Block的ByteDataView
      final parentView = _parent.getByteDataView();
      final subView = parentView.subView(
        _startOffset,
        _startOffset + _sliceLength,
      );

      // 分块读取数据
      int bytesRead = 0;
      while (bytesRead < size) {
        final int bytesToRead =
            (bytesRead + chunkSize <= size) ? chunkSize : size - bytesRead;

        final chunkView = subView.subView(bytesRead, bytesRead + bytesToRead);
        yield chunkView.toUint8List();
        bytesRead += bytesToRead;
      }
      return;
    }

    // 处理多个块的情况，优化跨块边界的读取
    if (_chunks.length == 1) {
      // 单个块可以使用sublist高效分块
      final chunk = _chunks[0];
      int offset = 0;
      while (offset < size) {
        final int end =
            (offset + chunkSize <= size) ? offset + chunkSize : size;
        yield chunk.sublist(offset, end);
        offset = end;
      }
      return;
    }

    // 对于多个块，使用ByteDataView分块处理
    final view = getByteDataView();
    int bytesRead = 0;
    while (bytesRead < size) {
      final int bytesToRead =
          (bytesRead + chunkSize <= size) ? chunkSize : size - bytesRead;

      final chunkView = view.subView(bytesRead, bytesRead + bytesToRead);
      yield chunkView.toUint8List();
      bytesRead += bytesToRead;
    }
  }

  /// Convenience static method to create an empty Block.
  ///
  /// Example:
  /// ```dart
  /// final emptyBlock = Block.empty(type: 'text/plain');
  /// ```
  static Block empty({String type = ''}) {
    return Block([], type: type);
  }

  /// 自定义缓存设置
  ///
  /// 可设置缓存的最大内存使用限制（字节）
  ///
  /// ```dart
  /// // 设置缓存最大为20MB
  /// Block.setCacheLimit(20 * 1024 * 1024);
  /// ```
  static void setCacheLimit(int maxBytes) {
    BlockCache.instance.maxMemoryCost = maxBytes;
  }

  /// 获取当前缓存使用量（字节）
  static int getCacheUsage() {
    return BlockCache.instance.totalMemoryCost;
  }

  /// 设置缓存项过期时间（毫秒）
  ///
  /// ```dart
  /// // 设置缓存项过期时间为10分钟
  /// Block.setCacheExpirationTime(10 * 60 * 1000);
  /// ```
  static void setCacheExpirationTime(int milliseconds) {
    BlockCache.instance.defaultExpirationMs = milliseconds;
  }

  /// 清空所有缓存
  static void clearCache() {
    BlockCache.instance.clear();
  }

  /// 获取缓存的Block
  ///
  /// 通过指定的键查找缓存中的Block
  /// 如果未找到或已过期，返回null
  static Block? getFromCache(String key) {
    return BlockCache.instance.get<Block>(key);
  }

  /// 存储Block到缓存
  ///
  /// [key] 缓存键
  /// [block] 要缓存的Block
  /// [priority] 优先级，可选值：'high', 'medium', 'low'，默认为'medium'
  static void putToCache(
    String key,
    Block block, {
    String priority = 'medium',
  }) {
    CachePriority cachePriority;

    switch (priority.toLowerCase()) {
      case 'high':
        cachePriority = CachePriority.high;
        break;
      case 'low':
        cachePriority = CachePriority.low;
        break;
      case 'medium':
      default:
        cachePriority = CachePriority.medium;
        break;
    }

    // 如果Block太大超过缓存限制，直接返回不缓存
    if (block._memoryCost > BlockCache.instance.maxMemoryCost) {
      return;
    }

    BlockCache.instance.put<Block>(
      key: key,
      data: block,
      memoryCost: block._memoryCost,
      priority: cachePriority,
    );
  }

  /// 从缓存中移除指定的Block
  static void removeFromCache(String key) {
    BlockCache.instance.remove(key);
  }

  /// 获取数据去重的统计信息
  ///
  /// 返回一个包含以下信息的Map：
  /// - uniqueBlockCount: 唯一数据块的数量
  /// - totalBytes: 存储的总字节数
  /// - totalRefCount: 总引用计数
  /// - totalSavedMemory: 总共节省的内存（字节）
  /// - duplicateBlockCount: 重复数据的块计数
  ///
  /// 示例:
  /// ```dart
  /// final report = Block.getDataDeduplicationReport();
  /// print('Saved ${report['totalSavedMemory']} bytes');
  /// ```
  static Map<String, dynamic> getDataDeduplicationReport() {
    return DataStore.instance.getReport();
  }

  /// 获取数据去重节省的总内存（字节）
  ///
  /// 示例:
  /// ```dart
  /// final savedMemory = Block.getDataDeduplicationSavedMemory();
  /// print('Saved $savedMemory bytes');
  /// ```
  static int getDataDeduplicationSavedMemory() {
    return DataStore.instance.totalSavedMemory;
  }

  /// 获取数据去重检测到的重复块数量
  ///
  /// 示例:
  /// ```dart
  /// final duplicateCount = Block.getDataDeduplicationDuplicateCount();
  /// print('Found $duplicateCount duplicate blocks');
  /// ```
  static int getDataDeduplicationDuplicateCount() {
    return DataStore.instance.duplicateBlockCount;
  }

  /// 重置数据去重统计
  static void resetDataDeduplication() {
    DataStore.instance.resetStatistics();
  }

  /// 强制更新内存统计数据
  ///
  /// 这个方法主要用于测试和基准测试，强制更新内存统计数据。
  /// 在正常使用中不需要调用此方法。
  ///
  /// 注意：此方法不会触发垃圾回收，只会更新已知的内存统计数据。
  static void forceUpdateMemoryStatistics() {
    // 这里不做实际的更新，因为内存统计是通过引用计数和finalizer自动更新的
    // 但我们可以触发一些内部操作，如清理未引用的数据
    DataStore.instance.cleanUnreferencedData();

    // 更新数据去重统计
    DataStore.instance.updateStatistics();

    // 打印当前内存统计，帮助调试
    print('DEBUG: Current memory statistics:');
    print('  Total memory usage: $_totalMemoryUsage bytes');
    print('  Active block count: $_activeBlockCount');
    print('  Data deduplication:');
    print('    Duplicate count: ${DataStore.instance.duplicateBlockCount}');
    print('    Saved memory: ${DataStore.instance.totalSavedMemory} bytes');
  }

  /// 设置自动内存监控器，定期检查内存使用情况
  ///
  /// [intervalMs] - 检查间隔（毫秒）
  /// [memoryLimit] - 内存使用上限（字节）
  ///
  /// 返回一个用于停止监控的函数
  ///
  /// 示例:
  /// ```dart
  /// // 开始每5秒监控一次，内存上限设为100MB
  /// final stopMonitor = Block.startMemoryMonitor(
  ///   intervalMs: 5000,
  ///   memoryLimit: 100 * 1024 * 1024,
  /// );
  ///
  /// // 稍后停止监控
  /// stopMonitor();
  /// ```
  static Function startMemoryMonitor({
    int intervalMs = 2000,
    int? memoryLimit,
  }) {
    if (memoryLimit != null) {
      setMemoryUsageLimit(memoryLimit);
    }

    // 创建定时器定期检查内存使用
    bool isRunning = true;
    void checkMemory() {
      if (!isRunning) return;

      // 强制更新内存统计
      forceUpdateMemoryStatistics();

      // 检查内存压力
      _checkMemoryPressure();

      // 如果内存使用率超过80%，主动减少内存占用
      if (_memoryUsageLimit != null) {
        final double usageRatio = _totalMemoryUsage / _memoryUsageLimit!;
        if (usageRatio > 0.8) {
          reduceMemoryUsage();
        }
      }

      // 安排下一次检查
      Future.delayed(Duration(milliseconds: intervalMs), checkMemory);
    }

    // 启动定时检查
    checkMemory();

    // 返回停止函数
    return () {
      isRunning = false;
      if (memoryLimit != null) {
        setMemoryUsageLimit(null); // 移除限制
      }
    };
  }

  /// 处理块数据，确保数据已加载
  void _processData() {
    if (_dataProcessed) return;

    // 处理原始部分数据
    if (_rawParts != null) {
      for (final part in _rawParts) {
        if (part is String) {
          final bytes = Uint8List.fromList(utf8.encode(part));
          // 存储数据，可能返回已存在的数据块（去重）
          // 传递this作为sourceBlock，用于跟踪数据使用
          final storedData = DataStore.instance.store(bytes, sourceBlock: this);
          _chunks.add(storedData);
        } else if (part is Uint8List) {
          // 传递this作为sourceBlock，用于跟踪数据使用
          final storedData = DataStore.instance.store(part, sourceBlock: this);
          _chunks.add(storedData);
        } else if (part is ByteData) {
          final bytes = Uint8List.view(
            part.buffer,
            part.offsetInBytes,
            part.lengthInBytes,
          );
          // 传递this作为sourceBlock，用于跟踪数据使用
          final storedData = DataStore.instance.store(bytes, sourceBlock: this);
          _chunks.add(storedData);
        } else if (part is Block) {
          // 对于嵌套Block，获取其所有数据块
          part._processData(); // 确保数据已处理
          _chunks.addAll(part._chunks);
        }
      }

      // 计算总长度
      _sliceLength = _calculateChunksSize(_chunks);
      // 由于_rawParts是final无法设为null，我们用清空内容的方式释放资源
      (_rawParts).clear();
    }

    _dataProcessed = true;
  }

  /// Calculate the total size of all chunks
  static int _calculateChunksSize(List<Uint8List> chunks) {
    if (chunks.isEmpty) {
      return 0;
    }

    int totalSize = 0;
    for (final chunk in chunks) {
      totalSize += chunk.length;
    }
    return totalSize;
  }
}
