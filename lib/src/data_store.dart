// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'block_cache.dart';
import 'memory_manager.dart';
import 'memory_pressure_level.dart';
import 'shared_data.dart';

// 前向声明，避免循环引用
// 我们使用类型参数替代直接定义，避免命名冲突
typedef BlockType = Object;

/// 数据去重存储类，用于保存唯一的数据块
///
/// 这是一个单例类，用于管理所有唯一的数据块。
/// 当创建Block时，会先检查数据是否已存在，如果存在则复用。
class DataStore {
  /// 单例实例
  static final DataStore _instance = DataStore._();

  /// 获取单例实例
  static DataStore get instance => _instance;

  /// 私有构造函数
  DataStore._();

  /// 存储数据块的哈希表
  ///
  /// 键是数据块的哈希值，值是数据块及其引用计数
  final Map<String, SharedData> _store = {};

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
  Uint8List store(Uint8List data, {BlockType? sourceBlock}) {
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
      _store[specificHash] = SharedData(data, 1);

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
    _store[hash] = SharedData(data, 1);

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
  void release(Uint8List data, {BlockType? sourceBlock}) {
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
    freedBytes += BlockCache.instance.clearByPressureLevel(
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
    print('DEBUG: DataStore statistics:');
    print('  Store size: ${_store.length}');
    for (final entry in _store.entries) {
      print(
        '  - Hash: ${entry.key}, RefCount: ${entry.value.refCount}, Size: ${entry.value.data.length}',
      );
    }
  }
}
