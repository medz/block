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

import 'deferred_operation.dart';
import 'memory_manager.dart';

/// 表示对原始二进制数据的视图，无需复制数据
///
/// 这个类允许在不复制数据的情况下访问底层二进制数据，
/// 提供了类似于ByteData的接口，但保留了对原始数据的引用。
class ByteDataView {
  /// 对原始数据的引用
  final List<Uint8List> _chunks;

  /// 数据的总长度
  final int length;

  /// 如果是分片，则表示起始偏移量
  final int _offset;

  /// 父视图（如果这是一个子视图）
  final ByteDataView? _parent;

  /// 创建一个新的数据视图
  ///
  /// [chunks] 是底层数据块的列表
  /// [length] 是数据的总长度
  ByteDataView(this._chunks, this.length) : _offset = 0, _parent = null;

  /// 创建一个子视图
  ///
  /// [parent] 是父视图
  /// [offset] 是在父视图中的起始位置
  /// [length] 是子视图的长度
  ByteDataView._(this._parent, this._offset, this.length) : _chunks = [];

  /// 创建一个子视图，表示原始数据的一部分，无需复制
  ByteDataView subView(int start, [int? end]) {
    final int endOffset = end ?? length;

    if (start < 0) start = 0;
    if (endOffset > length) throw RangeError('End offset exceeds view length');
    if (start >= endOffset) return ByteDataView([], 0);

    return ByteDataView._(this, start, endOffset - start);
  }

  /// 获取指定位置的字节
  int getUint8(int byteOffset) {
    if (byteOffset < 0 || byteOffset >= length) {
      throw RangeError('Offset out of range');
    }

    if (_parent != null) {
      return _parent.getUint8(_offset + byteOffset);
    }

    // 定位到正确的块
    int currentOffset = 0;
    for (final chunk in _chunks) {
      if (byteOffset < currentOffset + chunk.length) {
        return chunk[byteOffset - currentOffset];
      }
      currentOffset += chunk.length;
    }

    throw StateError('Unable to locate byte at offset $byteOffset');
  }

  /// 将数据复制到目标缓冲区
  void copyTo(Uint8List target, [int targetOffset = 0]) {
    if (targetOffset < 0) {
      throw RangeError('Target offset out of range');
    }

    if (targetOffset + length > target.length) {
      throw RangeError('Target buffer too small');
    }

    if (_parent != null) {
      _parent._copyRange(target, targetOffset, _offset, _offset + length);
      return;
    }

    _copyRange(target, targetOffset, 0, length);
  }

  /// 内部方法：将指定范围的数据复制到目标缓冲区
  void _copyRange(Uint8List target, int targetOffset, int start, int end) {
    if (_parent != null) {
      _parent._copyRange(target, targetOffset, _offset + start, _offset + end);
      return;
    }

    int sourceOffset = 0;
    int currentTargetOffset = targetOffset;
    int remainingBytes = end - start;

    // 跳过start之前的块
    for (final chunk in _chunks) {
      if (sourceOffset + chunk.length <= start) {
        sourceOffset += chunk.length;
        continue;
      }

      // 计算此块中的起始位置和复制长度
      final int chunkStart = start > sourceOffset ? start - sourceOffset : 0;
      final int bytesToCopy =
          (sourceOffset + chunk.length > end)
              ? remainingBytes
              : chunk.length - chunkStart;

      // 复制此块的数据
      target.setRange(
        currentTargetOffset,
        currentTargetOffset + bytesToCopy,
        chunk,
        chunkStart,
      );

      currentTargetOffset += bytesToCopy;
      remainingBytes -= bytesToCopy;

      if (remainingBytes <= 0) break;
      sourceOffset += chunk.length;
    }
  }

  /// 将视图转换为Uint8List，此操作会复制数据
  Uint8List toUint8List() {
    final result = Uint8List(length);
    copyTo(result);
    return result;
  }

  /// 检查此视图是否为单个连续的数据块
  bool get isContinuous => _parent == null && _chunks.length == 1;

  /// 如果视图是单个连续数据块，直接返回原始引用；否则返回null
  ///
  /// 使用此方法可以在某些情况下完全避免数据复制
  Uint8List? get continuousData {
    if (isContinuous) {
      return _chunks[0];
    }

    if (_parent != null &&
        _parent.isContinuous &&
        _offset == 0 &&
        length == _parent.length) {
      return _parent.continuousData;
    }

    return null;
  }

  /// 获取一个字节视图
  ByteBuffer get buffer => toUint8List().buffer;
}

/// 数据去重存储类，用于保存唯一的数据块
///
/// 这是一个单例类，用于管理所有唯一的数据块。
/// 当创建Block时，会先检查数据是否已存在，如果存在则复用。
class _DataStore {
  /// 单例实例
  static final _DataStore _instance = _DataStore._();

  /// 获取单例实例
  static _DataStore get instance => _instance;

  /// 私有构造函数
  _DataStore._();

  /// 存储数据块的哈希表
  ///
  /// 键是数据块的哈希值，值是数据块及其引用计数
  final Map<String, _SharedData> _store = {};

  /// 总共节省的内存（字节）
  int _totalSavedMemory = 0;

  /// 重复数据的块计数
  int _duplicateBlockCount = 0;

  /// 重置统计数据
  ///
  /// 重置所有统计计数器，但不清除已存储的数据
  void resetStatistics() {
    _totalSavedMemory = 0;
    _duplicateBlockCount = 0;
  }

  /// 获取总共节省的内存（字节）
  int get totalSavedMemory => _totalSavedMemory;

  /// 获取重复数据的块计数
  int get duplicateBlockCount => _duplicateBlockCount;

  /// 计算数据块的哈希值
  ///
  /// 使用简单的算法计算数据的哈希值，以便快速查找
  String _computeHash(Uint8List data) {
    // 对于小数据块，直接使用完整数据计算
    if (data.length < 1024) {
      return _hashData(data);
    }

    // 对于大数据块，只使用采样点计算哈希值以提高性能
    // 采样开头、中间和结尾的数据
    final samples = <int>[];

    // 采样开头的512字节
    final headSize = data.length > 512 ? 512 : data.length;
    samples.addAll(data.sublist(0, headSize));

    // 如果数据足够大，采样中间的512字节
    if (data.length > 1024) {
      final middleStart = (data.length ~/ 2) - 256;
      final middleSize =
          data.length - middleStart > 512 ? 512 : data.length - middleStart;
      samples.addAll(data.sublist(middleStart, middleStart + middleSize));
    }

    // 如果数据足够大，采样末尾的512字节
    if (data.length > 512) {
      final tailStart = data.length - 512;
      samples.addAll(data.sublist(tailStart));
    }

    // 添加数据长度作为哈希的一部分
    final lengthBytes = Uint8List(8);
    final view = ByteData.view(lengthBytes.buffer);
    view.setUint64(0, data.length);
    samples.addAll(lengthBytes);

    return _hashData(Uint8List.fromList(samples));
  }

  /// 对数据进行哈希计算
  String _hashData(Uint8List data) {
    // 一个简单但有效的哈希算法
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data[i];
      hash = hash & 0xFFFFFFFF; // 保证是32位整数
    }

    // 对于长度相同但内容极其相似的数据，加入一些随机性
    final subSamples = <int>[];
    if (data.length >= 16) {
      // 采样一些特殊位置
      for (int i = 0; i < 16; i++) {
        final pos = (i * data.length ~/ 16);
        subSamples.add(data[pos]);
      }
    }

    int subHash = 0;
    for (int i = 0; i < subSamples.length; i++) {
      subHash = ((subHash << 7) - subHash) + subSamples[i];
      subHash = subHash & 0xFFFFFFFF;
    }

    // 组合两个哈希值
    return '$hash:$subHash:${data.length}';
  }

  /// 检查两个数据块是否完全相同
  bool _isDataEqual(Uint8List data1, Uint8List data2) {
    if (data1.length != data2.length) {
      return false;
    }

    for (int i = 0; i < data1.length; i++) {
      if (data1[i] != data2[i]) {
        return false;
      }
    }

    return true;
  }

  /// 存储或获取共享数据
  ///
  /// 如果数据已存在，返回现有数据；否则存储并返回新数据
  ///
  /// Optional [sourceBlock] is used to track data usage by blocks
  Uint8List store(Uint8List data, {Block? sourceBlock}) {
    // 空数据直接返回
    if (data.isEmpty) {
      return data;
    }

    // 计算哈希值
    final hash = _computeHash(data);

    // 检查是否已存在相同哈希的数据
    if (_store.containsKey(hash)) {
      final sharedData = _store[hash]!;

      // 哈希冲突检查：确保数据真的相同
      if (_isDataEqual(data, sharedData.data)) {
        // 增加引用计数
        sharedData.refCount++;

        // 记录节省的内存
        _totalSavedMemory += data.length;
        _duplicateBlockCount++;

        // 集成内存管理器 - 如果提供了sourceBlock
        if (sourceBlock != null) {
          // 通知内存管理器关联数据与Block
          MemoryManager.instance.associateDataWithBlock(
            sourceBlock.hashCode.toString(),
            hash,
            data.length,
          );
        }

        return sharedData.data;
      }

      // 哈希冲突，但数据不同，使用更具体的哈希值
      final specificHash = '$hash:${DateTime.now().microsecondsSinceEpoch}';

      // 存储新数据
      _store[specificHash] = _SharedData(data, 1);

      // 集成内存管理器 - 如果提供了sourceBlock
      if (sourceBlock != null) {
        // 通知内存管理器关联数据与Block
        MemoryManager.instance.associateDataWithBlock(
          sourceBlock.hashCode.toString(),
          specificHash,
          data.length,
        );
      }

      return data;
    }

    // 存储新数据
    _store[hash] = _SharedData(data, 1);

    // 集成内存管理器 - 如果提供了sourceBlock
    if (sourceBlock != null) {
      // 通知内存管理器关联数据与Block
      MemoryManager.instance.associateDataWithBlock(
        sourceBlock.hashCode.toString(),
        hash,
        data.length,
      );
    }

    return data;
  }

  /// 数据引用计数减一，如果引用计数为0则从存储中移除
  ///
  /// Optional [sourceBlock] is used to track data usage by blocks
  void release(Uint8List data, {Block? sourceBlock}) {
    // 空数据直接返回
    if (data.isEmpty) {
      return;
    }

    // 计算数据大小（用于内存管理器）
    final dataSize = data.length;

    // 计算哈希值
    final hash = _computeHash(data);

    // 检查是否存在相同哈希的数据
    if (_store.containsKey(hash)) {
      final sharedData = _store[hash]!;

      // 哈希冲突检查：确保数据真的相同
      if (_isDataEqual(data, sharedData.data)) {
        sharedData.refCount--;

        // 集成内存管理器 - 如果提供了sourceBlock
        if (sourceBlock != null) {
          // 通知内存管理器解除数据与Block的关联
          MemoryManager.instance.dissociateDataFromBlock(
            sourceBlock.hashCode.toString(),
            hash,
            dataSize,
          );
        }

        // 如果引用计数为0，从存储中移除
        if (sharedData.refCount <= 0) {
          _store.remove(hash);
        }
        return;
      }
    }

    // 尝试查找数据（在哈希冲突的情况下）
    for (final entry in _store.entries) {
      if (_isDataEqual(data, entry.value.data)) {
        entry.value.refCount--;

        // 集成内存管理器 - 如果提供了sourceBlock
        if (sourceBlock != null) {
          // 通知内存管理器解除数据与Block的关联
          MemoryManager.instance.dissociateDataFromBlock(
            sourceBlock.hashCode.toString(),
            entry.key,
            dataSize,
          );
        }

        // 如果引用计数为0，从存储中移除
        if (entry.value.refCount <= 0) {
          _store.remove(entry.key);
        }
        return;
      }
    }
  }

  /// 获取指定哈希对应的数据块
  Uint8List? getDataByHash(String hash) {
    final sharedData = _store[hash];
    return sharedData?.data;
  }

  /// 获取指定哈希对应的数据块引用计数
  int getReferenceCount(String hash) {
    final sharedData = _store[hash];
    return sharedData?.refCount ?? 0;
  }

  /// 清除所有未被引用的数据块
  int cleanUnreferencedData() {
    final keysToRemove = <String>[];
    int freedBytes = 0;

    for (final entry in _store.entries) {
      if (entry.value.refCount <= 0) {
        keysToRemove.add(entry.key);
        freedBytes += entry.value.data.length;
      }
    }

    for (final key in keysToRemove) {
      _store.remove(key);
    }

    return freedBytes;
  }

  /// 清理孤立的数据块（没有Block引用的数据）
  int cleanOrphanedData() {
    int freedBytes = 0;
    final keysToRemove = <String>[];

    // 查询 MemoryManager 获取每个数据块的引用状态
    for (final entry in _store.entries) {
      final dataId = entry.key;
      if (MemoryManager.instance.getDataReferenceCount(dataId) <= 0) {
        keysToRemove.add(dataId);
        freedBytes += entry.value.data.length;
      }
    }

    // 移除未引用的数据
    for (final key in keysToRemove) {
      _store.remove(key);
    }

    return freedBytes;
  }

  /// 在内存压力下释放数据
  ///
  /// 目前只清理未被引用的数据块，未来可以添加更智能的策略
  int reduceMemoryUsage() {
    // 清理缓存和未引用的共享数据
    int freedBytes = 0;

    // 清理缓存
    freedBytes += _BlockCache.instance.clearByPressureLevel(
      MemoryPressureLevel.medium,
    );

    // 清理未引用的共享数据
    freedBytes += cleanUnreferencedData();

    return freedBytes;
  }

  /// 获取数据存储状态报告
  Map<String, dynamic> getReport() {
    int totalBytes = 0;
    int totalRefCount = 0;

    for (final entry in _store.values) {
      totalBytes += entry.data.length;
      totalRefCount += entry.refCount;
    }

    return {
      'uniqueBlockCount': _store.length,
      'totalBytes': totalBytes,
      'totalRefCount': totalRefCount,
      'totalSavedMemory': _totalSavedMemory,
      'duplicateBlockCount': _duplicateBlockCount,
    };
  }

  /// 更新内存统计数据
  ///
  /// 这个方法会重新计算所有内存统计数据，确保它们的准确性。
  /// 主要用于测试和基准测试。
  void updateStatistics() {
    // 重置统计数据
    _totalSavedMemory = 0;
    _duplicateBlockCount = 0;

    // 重新计算统计数据
    for (final entry in _store.values) {
      if (entry.refCount > 1) {
        // 对于每个引用计数大于1的数据块，计算节省的内存
        _totalSavedMemory += entry.data.length * (entry.refCount - 1);
        _duplicateBlockCount += entry.refCount - 1;
      }
    }

    // 打印详细的统计信息，帮助调试
    print('DEBUG: _DataStore statistics:');
    print('  Store size: ${_store.length}');
    for (final entry in _store.entries) {
      print(
        '  - Hash: ${entry.key}, RefCount: ${entry.value.refCount}, Size: ${entry.value.data.length}',
      );
    }
  }
}

/// 共享数据结构，包含数据和引用计数
class _SharedData {
  /// 数据内容
  final Uint8List data;

  /// 引用计数
  int refCount;

  _SharedData(this.data, this.refCount);
}

/// 用于跟踪Block内存使用的辅助类
class _BlockMemoryTracker {
  /// 内存成本
  final int memoryCost;

  /// 需要释放的数据块引用
  final List<Uint8List> dataToRelease;

  _BlockMemoryTracker(this.memoryCost, this.dataToRelease);
}

/// 内存压力等级
enum MemoryPressureLevel {
  /// 正常内存使用，无压力
  none,

  /// 轻度内存压力，建议释放非必要缓存
  low,

  /// 中度内存压力，应该主动释放缓存
  medium,

  /// 高度内存压力，必须释放所有可释放资源
  high,

  /// 危险级别，可能导致程序崩溃
  critical,
}

/// 缓存项的优先级
enum _CachePriority {
  /// 高优先级缓存，仅在高内存压力下清理
  high,

  /// 中优先级缓存，在中度内存压力下清理
  medium,

  /// 低优先级缓存，在轻度内存压力下清理
  low,
}

/// 缓存项
class _CacheItem<T> {
  /// 缓存的数据
  final T data;

  /// 缓存项的内存占用（字节）
  final int memoryCost;

  /// 缓存项的优先级
  final _CachePriority priority;

  /// 最后访问时间
  DateTime lastAccessed = DateTime.now();

  /// 创建时间
  final DateTime createdAt = DateTime.now();

  _CacheItem({
    required this.data,
    required this.memoryCost,
    this.priority = _CachePriority.medium,
  });

  /// 更新最后访问时间
  void touch() {
    lastAccessed = DateTime.now();
  }
}

/// 缓存池管理类
class _BlockCache {
  /// 单例实例
  static final _BlockCache _instance = _BlockCache._();

  /// 获取单例实例
  static _BlockCache get instance => _instance;

  /// 私有构造函数
  _BlockCache._();

  /// 缓存池，按照Key存储缓存项
  final Map<String, _CacheItem> _cache = {};

  /// 缓存池内存使用总量（字节）
  int _totalMemoryCost = 0;

  /// 缓存池最大内存限制（字节），默认为10MB
  int _maxMemoryCost = 10 * 1024 * 1024;

  /// 缓存项过期时间（毫秒），默认为5分钟
  int _defaultExpirationMs = 5 * 60 * 1000;

  /// 获取缓存池内存使用量
  int get totalMemoryCost => _totalMemoryCost;

  /// 设置缓存池最大内存限制
  set maxMemoryCost(int value) {
    _maxMemoryCost = value;
    _checkAndCleanCache();
  }

  /// 获取缓存池最大内存限制
  int get maxMemoryCost => _maxMemoryCost;

  /// 设置缓存项默认过期时间（毫秒）
  set defaultExpirationMs(int value) {
    _defaultExpirationMs = value;
  }

  /// 从缓存中获取数据
  T? get<T>(String key) {
    final item = _cache[key];
    if (item == null) {
      return null;
    }

    // 检查是否过期
    if (_isExpired(item)) {
      _removeItem(key);
      return null;
    }

    // 更新最后访问时间
    item.touch();
    return item.data as T;
  }

  /// 将数据存入缓存，可选设置优先级
  ///
  /// 优先级可以是 'low', 'medium', 或 'high'，默认为 'medium'
  /// 在内存压力下，低优先级缓存会先被清理
  void put<T>({
    required String key,
    required T data,
    required int memoryCost,
    _CachePriority priority = _CachePriority.medium,
  }) {
    // 如果已存在此key，先移除旧数据
    if (_cache.containsKey(key)) {
      _removeItem(key);
    }

    // 如果添加新缓存会超过最大限制，先清理一些旧缓存
    if (_totalMemoryCost + memoryCost > _maxMemoryCost) {
      _evictCache(requiredSpace: memoryCost);
    }

    // 添加新缓存项
    final item = _CacheItem<T>(
      data: data,
      memoryCost: memoryCost,
      priority: priority,
    );
    _cache[key] = item;
    _totalMemoryCost += memoryCost;
  }

  /// 从缓存中移除数据
  void remove(String key) {
    _removeItem(key);
  }

  /// 清空所有缓存
  void clear() {
    _cache.clear();
    _totalMemoryCost = 0;
  }

  /// 检查缓存项是否过期
  bool _isExpired(_CacheItem item) {
    final now = DateTime.now();
    return now.difference(item.lastAccessed).inMilliseconds >
        _defaultExpirationMs;
  }

  /// 内部移除缓存项的方法
  void _removeItem(String key) {
    final item = _cache.remove(key);
    if (item != null) {
      _totalMemoryCost -= item.memoryCost;
    }
  }

  /// 根据优先级清理指定内存压力下的缓存
  int clearByPressureLevel(MemoryPressureLevel level) {
    int freedBytes = 0;

    switch (level) {
      case MemoryPressureLevel.low:
        // 轻度压力：只清理低优先级缓存
        freedBytes = _clearByPriority(_CachePriority.low);
        break;
      case MemoryPressureLevel.medium:
        // 中度压力：清理低优先级和中优先级缓存
        freedBytes = _clearByPriority(_CachePriority.low);
        freedBytes += _clearByPriority(_CachePriority.medium);
        break;
      case MemoryPressureLevel.high:
      case MemoryPressureLevel.critical:
        // 高压力或危险级别：清理所有缓存
        freedBytes = _totalMemoryCost;
        clear();
        break;
      case MemoryPressureLevel.none:
        // 无压力：不清理，只进行常规过期检查
        freedBytes = _cleanExpiredItems();
        break;
    }

    return freedBytes;
  }

  /// 清理指定优先级的缓存
  int _clearByPriority(_CachePriority priority) {
    int freedBytes = 0;
    final keysToRemove = <String>[];

    _cache.forEach((key, item) {
      if (item.priority == priority) {
        freedBytes += item.memoryCost;
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _removeItem(key);
    }

    return freedBytes;
  }

  /// 清理过期的缓存项
  int _cleanExpiredItems() {
    int freedBytes = 0;
    final keysToRemove = <String>[];

    _cache.forEach((key, item) {
      if (_isExpired(item)) {
        freedBytes += item.memoryCost;
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _removeItem(key);
    }

    return freedBytes;
  }

  /// 腾出指定空间的缓存
  void _evictCache({required int requiredSpace}) {
    // 先清理过期缓存
    _cleanExpiredItems();

    // 如果还不够，按照最后访问时间清理
    if (_totalMemoryCost + requiredSpace > _maxMemoryCost) {
      // 按照最后访问时间排序，优先清理最早访问的
      final sortedItems =
          _cache.entries.toList()..sort(
            (a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed),
          );

      // 从最早访问的开始移除，直到空间足够
      for (final entry in sortedItems) {
        // 不移除高优先级的缓存，除非实在没有空间
        if (entry.value.priority == _CachePriority.high &&
            _totalMemoryCost + requiredSpace - entry.value.memoryCost <=
                _maxMemoryCost) {
          continue;
        }

        _removeItem(entry.key);

        // 如果空间已足够，退出循环
        if (_totalMemoryCost + requiredSpace <= _maxMemoryCost) {
          break;
        }
      }
    }
  }

  /// 检查并清理缓存，在内存使用超过限制时调用
  void _checkAndCleanCache() {
    if (_totalMemoryCost > _maxMemoryCost) {
      // 优先清理过期的
      _cleanExpiredItems();

      // 如果还是超过限制，按照最后访问时间和优先级清理
      if (_totalMemoryCost > _maxMemoryCost) {
        _evictCache(requiredSpace: 0);
      }
    }
  }
}

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
    freedBytes += _BlockCache.instance.clearByPressureLevel(
      MemoryPressureLevel.medium,
    );

    // 清理未引用的共享数据
    freedBytes += _DataStore.instance.reduceMemoryUsage();

    return freedBytes;
  }

  /// 根据内存压力级别自动释放内存
  static int _autoReduceMemoryUsage(MemoryPressureLevel level) {
    int freedBytes = 0;

    switch (level) {
      case MemoryPressureLevel.low:
        // 轻度压力：清理非关键缓存
        freedBytes = _BlockCache.instance.clearByPressureLevel(level);
        // 增加当轻度压力下的缓存和未使用数据的清理频率
        freedBytes += _DataStore.instance.cleanUnreferencedData();
        break;
      case MemoryPressureLevel.medium:
        // 中度压力：清理所有缓存
        freedBytes = _BlockCache.instance.clearByPressureLevel(level);
        // 清理未引用的共享数据
        freedBytes += _DataStore.instance.reduceMemoryUsage();
        break;
      case MemoryPressureLevel.high:
      case MemoryPressureLevel.critical:
        // 高压力：清理所有缓存并强制释放所有可能的内存
        freedBytes = _BlockCache.instance.clearByPressureLevel(level);
        freedBytes += reduceMemoryUsage();

        // 在高压力或危急情况下，主动触发垃圾回收
        if (level == MemoryPressureLevel.critical) {
          // 使用间接方式提示垃圾回收器工作
          _suggestGarbageCollection();
        }
        break;
      case MemoryPressureLevel.none:
        // 无压力：只清理过期缓存和未引用的数据
        freedBytes = _BlockCache.instance.clearByPressureLevel(level);
        // 清理未引用的共享数据
        freedBytes += _DataStore.instance.cleanUnreferencedData();
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
  static final _finalizer = Finalizer<_BlockMemoryTracker>((tracker) {
    // 当Block被垃圾回收时，减少总内存使用量统计
    _totalMemoryUsage -= tracker.memoryCost;
    _activeBlockCount--;

    // 释放数据块引用
    for (final data in tracker.dataToRelease) {
      _DataStore.instance.release(data);
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
      _BlockMemoryTracker(_memoryCost, dataToRelease),
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
      // 使用 _DataStore.store 方法存储数据，以便跟踪数据去重
      final storedBytes = _DataStore.instance.store(bytes);
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
          normalizedParts.add(_DataStore.instance.store(chunk));
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
        chunks.add(_DataStore.instance.store(currentChunk));
        currentChunk = null;
        currentSize = 0;
      }
    }

    // Add any remaining data
    if (currentChunk != null && currentSize > 0) {
      // Create right-sized final chunk
      final finalChunk = Uint8List(currentSize);
      finalChunk.setRange(0, currentSize, currentChunk, 0);
      chunks.add(_DataStore.instance.store(finalChunk));
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
    return _DataStore.instance.store(rawData);
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
    _BlockCache.instance.maxMemoryCost = maxBytes;
  }

  /// 获取当前缓存使用量（字节）
  static int getCacheUsage() {
    return _BlockCache.instance.totalMemoryCost;
  }

  /// 设置缓存项过期时间（毫秒）
  ///
  /// ```dart
  /// // 设置缓存项过期时间为10分钟
  /// Block.setCacheExpirationTime(10 * 60 * 1000);
  /// ```
  static void setCacheExpirationTime(int milliseconds) {
    _BlockCache.instance.defaultExpirationMs = milliseconds;
  }

  /// 清空所有缓存
  static void clearCache() {
    _BlockCache.instance.clear();
  }

  /// 获取缓存的Block
  ///
  /// 通过指定的键查找缓存中的Block
  /// 如果未找到或已过期，返回null
  static Block? getFromCache(String key) {
    return _BlockCache.instance.get<Block>(key);
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
    _CachePriority cachePriority;

    switch (priority.toLowerCase()) {
      case 'high':
        cachePriority = _CachePriority.high;
        break;
      case 'low':
        cachePriority = _CachePriority.low;
        break;
      case 'medium':
      default:
        cachePriority = _CachePriority.medium;
        break;
    }

    // 如果Block太大超过缓存限制，直接返回不缓存
    if (block._memoryCost > _BlockCache.instance.maxMemoryCost) {
      return;
    }

    _BlockCache.instance.put<Block>(
      key: key,
      data: block,
      memoryCost: block._memoryCost,
      priority: cachePriority,
    );
  }

  /// 从缓存中移除指定的Block
  static void removeFromCache(String key) {
    _BlockCache.instance.remove(key);
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
    return _DataStore.instance.getReport();
  }

  /// 获取数据去重节省的总内存（字节）
  ///
  /// 示例:
  /// ```dart
  /// final savedMemory = Block.getDataDeduplicationSavedMemory();
  /// print('Saved $savedMemory bytes');
  /// ```
  static int getDataDeduplicationSavedMemory() {
    return _DataStore.instance.totalSavedMemory;
  }

  /// 获取数据去重检测到的重复块数量
  ///
  /// 示例:
  /// ```dart
  /// final duplicateCount = Block.getDataDeduplicationDuplicateCount();
  /// print('Found $duplicateCount duplicate blocks');
  /// ```
  static int getDataDeduplicationDuplicateCount() {
    return _DataStore.instance.duplicateBlockCount;
  }

  /// 重置数据去重统计
  static void resetDataDeduplication() {
    _DataStore.instance.resetStatistics();
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
    _DataStore.instance.cleanUnreferencedData();

    // 更新数据去重统计
    _DataStore.instance.updateStatistics();

    // 打印当前内存统计，帮助调试
    print('DEBUG: Current memory statistics:');
    print('  Total memory usage: $_totalMemoryUsage bytes');
    print('  Active block count: $_activeBlockCount');
    print('  Data deduplication:');
    print('    Duplicate count: ${_DataStore.instance.duplicateBlockCount}');
    print('    Saved memory: ${_DataStore.instance.totalSavedMemory} bytes');
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
          final storedData = _DataStore.instance.store(
            bytes,
            sourceBlock: this,
          );
          _chunks.add(storedData);
        } else if (part is Uint8List) {
          // 传递this作为sourceBlock，用于跟踪数据使用
          final storedData = _DataStore.instance.store(part, sourceBlock: this);
          _chunks.add(storedData);
        } else if (part is ByteData) {
          final bytes = Uint8List.view(
            part.buffer,
            part.offsetInBytes,
            part.lengthInBytes,
          );
          // 传递this作为sourceBlock，用于跟踪数据使用
          final storedData = _DataStore.instance.store(
            bytes,
            sourceBlock: this,
          );
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
