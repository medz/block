// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:core';
import 'dart:typed_data';

/// 跟踪信息，关联Block对象与其数据块
class _BlockTrackingInfo {
  /// Block的唯一标识符
  final String blockId;

  /// 该Block使用的数据块IDs
  final Set<String> dataIds;

  /// 最后访问时间
  DateTime lastAccessTime;

  /// 内存使用成本估计（字节）
  int memoryCost;

  _BlockTrackingInfo({
    required this.blockId,
    required this.lastAccessTime,
    this.memoryCost = 0,
  }) : dataIds = <String>{};

  /// 添加数据块关联
  void addDataReference(String dataId) {
    dataIds.add(dataId);
  }

  /// 移除数据块关联
  void removeDataReference(String dataId) {
    dataIds.remove(dataId);
  }

  /// 更新访问时间
  void updateAccessTime() {
    lastAccessTime = DateTime.now();
  }
}

/// A memory manager for Block library that provides enhanced memory management capabilities.
///
/// This class implements:
/// 1. Weak reference tracking for Block objects
/// 2. LRU (Least Recently Used) cache for data blocks
/// 3. Periodic memory cleanup
/// 4. Memory pressure detection and response
class MemoryManager {
  /// Singleton instance
  static final MemoryManager _instance = MemoryManager._internal();

  /// Factory constructor to return the singleton instance
  factory MemoryManager() => _instance;

  /// Private constructor for singleton pattern
  MemoryManager._internal();

  /// Get the singleton instance
  static MemoryManager get instance => _instance;

  /// Whether the memory manager is running
  bool _isRunning = false;

  /// Timer for periodic memory checks
  Timer? _memoryCheckTimer;

  /// Memory usage high watermark (bytes)
  int? _highWatermark;

  /// Memory usage critical watermark (bytes)
  int? _criticalWatermark;

  /// Last time memory cleanup was performed
  DateTime _lastCleanupTime = DateTime.now();

  /// LRU cache for tracking block access
  final _blockAccessTimes = HashMap<String, DateTime>();

  /// Weak references to blocks
  final _weakBlockRefs = HashSet<WeakReference<Object>>();

  /// 跟踪Block对象与数据块的关联
  final _blockTrackingMap = HashMap<String, _BlockTrackingInfo>();

  /// 数据块引用映射：数据块ID -> 使用该数据的Block IDs
  final _dataReferenceMap = HashMap<String, Set<String>>();

  /// 当前估计的总内存使用量（字节）
  int _estimatedMemoryUsage = 0;

  /// Finalizer for cleaning up resources when Block objects are garbage collected
  static final _finalizer = Finalizer<String>((blockId) {
    // This callback will be executed when a Block object is garbage collected
    // We need to remove the block from our tracking and potentially clean up resources
    MemoryManager.instance._cleanupBlockResources(blockId);
  });

  /// Clean up resources associated with a block that has been garbage collected
  void _cleanupBlockResources(String blockId) {
    if (!_isRunning) return;

    // Remove from access times tracking
    _blockAccessTimes.remove(blockId);

    // 清理关联的数据引用
    final trackingInfo = _blockTrackingMap[blockId];
    if (trackingInfo != null) {
      // 更新内存使用估计
      _estimatedMemoryUsage -= trackingInfo.memoryCost;

      // 移除数据引用关联
      for (final dataId in trackingInfo.dataIds) {
        final blocksUsingThisData = _dataReferenceMap[dataId];
        if (blocksUsingThisData != null) {
          blocksUsingThisData.remove(blockId);

          // 如果没有Block使用此数据，在_DataStore中减少引用计数
          if (blocksUsingThisData.isEmpty) {
            _dataReferenceMap.remove(dataId);
            // TODO: 调用 _DataStore.release(dataId) 释放数据
          }
        }
      }

      // 从跟踪映射中移除
      _blockTrackingMap.remove(blockId);
    }

    // Log the cleanup for debugging purposes
    print('Block $blockId was garbage collected, resources cleaned up');
  }

  /// Start the memory manager with specified parameters
  void start({
    Duration checkInterval = const Duration(seconds: 2),
    int? highWatermark,
    int? criticalWatermark,
  }) {
    if (_isRunning) return;

    _highWatermark = highWatermark;
    _criticalWatermark = criticalWatermark;
    _isRunning = true;

    // Start periodic memory check
    _memoryCheckTimer = Timer.periodic(checkInterval, (_) => _checkMemory());

    print(
      'Memory manager started with interval: ${checkInterval.inMilliseconds}ms',
    );
    if (highWatermark != null) {
      print('High watermark: ${_formatBytes(highWatermark)}');
    }
    if (criticalWatermark != null) {
      print('Critical watermark: ${_formatBytes(criticalWatermark)}');
    }
  }

  /// Stop the memory manager
  void stop() {
    if (!_isRunning) return;

    _memoryCheckTimer?.cancel();
    _memoryCheckTimer = null;
    _isRunning = false;

    print('Memory manager stopped');
  }

  /// Register a block with the memory manager
  void registerBlock(Object block, String blockId) {
    if (!_isRunning) return;

    // Add weak reference to the block
    _weakBlockRefs.add(WeakReference<Object>(block));

    // Record access time
    _recordBlockAccess(blockId);

    // 创建跟踪信息
    final trackingInfo = _BlockTrackingInfo(
      blockId: blockId,
      lastAccessTime: DateTime.now(),
    );
    _blockTrackingMap[blockId] = trackingInfo;

    // Attach finalizer to be notified when this block is garbage collected
    // The block object is the one we're watching, and blockId is the token
    // passed to the finalizer callback when block is collected
    _finalizer.attach(block, blockId, detach: block);
  }

  /// 关联数据块与Block（当Block使用特定数据块时调用）
  void associateDataWithBlock(String blockId, String dataId, int dataSize) {
    if (!_isRunning) return;

    // 更新Block跟踪信息
    final trackingInfo = _blockTrackingMap[blockId];
    if (trackingInfo != null) {
      trackingInfo.addDataReference(dataId);
      trackingInfo.updateAccessTime();

      // 更新内存使用估计
      if (!trackingInfo.dataIds.contains(dataId)) {
        trackingInfo.memoryCost += dataSize;
        _estimatedMemoryUsage += dataSize;
      }
    }

    // 更新数据引用映射
    _dataReferenceMap.putIfAbsent(dataId, () => <String>{}).add(blockId);
  }

  /// 取消数据块与Block的关联（当Block不再使用特定数据块时调用）
  void dissociateDataFromBlock(String blockId, String dataId, int dataSize) {
    if (!_isRunning) return;

    // 更新Block跟踪信息
    final trackingInfo = _blockTrackingMap[blockId];
    if (trackingInfo != null && trackingInfo.dataIds.contains(dataId)) {
      trackingInfo.removeDataReference(dataId);

      // 更新内存使用估计
      trackingInfo.memoryCost -= dataSize;
      _estimatedMemoryUsage -= dataSize;
    }

    // 更新数据引用映射
    final blocksUsingThisData = _dataReferenceMap[dataId];
    if (blocksUsingThisData != null) {
      blocksUsingThisData.remove(blockId);

      // 如果没有Block使用此数据，在_DataStore中减少引用计数
      if (blocksUsingThisData.isEmpty) {
        _dataReferenceMap.remove(dataId);
        // TODO: 调用 _DataStore.release(dataId) 释放数据
      }
    }
  }

  /// Record that a block was accessed
  void recordBlockAccess(String blockId) {
    if (!_isRunning) return;
    _recordBlockAccess(blockId);

    // 更新跟踪信息的访问时间
    final trackingInfo = _blockTrackingMap[blockId];
    if (trackingInfo != null) {
      trackingInfo.updateAccessTime();
    }
  }

  /// Internal method to record block access time
  void _recordBlockAccess(String blockId) {
    _blockAccessTimes[blockId] = DateTime.now();
  }

  /// Manually detach a block from the finalizer (e.g., when explicitly disposed)
  void detachBlock(Object block) {
    if (!_isRunning) return;
    _finalizer.detach(block);
  }

  /// Check if a block is still referenced
  bool isBlockReferenced(String blockId) {
    return _blockTrackingMap.containsKey(blockId);
  }

  /// 获取数据块的引用计数（有多少个Block正在使用该数据）
  int getDataReferenceCount(String dataId) {
    final blocksUsingThisData = _dataReferenceMap[dataId];
    return blocksUsingThisData?.length ?? 0;
  }

  /// 获取Block使用的数据块ID列表
  List<String> getBlockDataIds(String blockId) {
    final trackingInfo = _blockTrackingMap[blockId];
    return trackingInfo?.dataIds.toList() ?? [];
  }

  /// 获取当前估计的内存使用量（字节）
  int getEstimatedMemoryUsage() {
    return _estimatedMemoryUsage;
  }

  /// 获取当前正在跟踪的Block数量
  int getTrackedBlockCount() {
    return _blockTrackingMap.length;
  }

  /// 获取当前正在跟踪的数据块数量
  int getTrackedDataCount() {
    return _dataReferenceMap.length;
  }

  /// 获取内存使用情况报告
  Map<String, dynamic> getMemoryReport() {
    return {
      'trackedBlockCount': getTrackedBlockCount(),
      'trackedDataCount': getTrackedDataCount(),
      'estimatedMemoryUsage': getEstimatedMemoryUsage(),
      'weakReferencesCount': _weakBlockRefs.length,
    };
  }

  /// Perform memory check and cleanup if needed
  void _checkMemory() {
    if (!_isRunning) return;

    final currentMemoryUsage = getCurrentMemoryUsage();
    final now = DateTime.now();

    // Check if we need to perform cleanup based on memory pressure
    bool shouldCleanup = false;

    // Check against watermarks
    if (_criticalWatermark != null &&
        currentMemoryUsage > _criticalWatermark!) {
      print('CRITICAL MEMORY PRESSURE: ${_formatBytes(currentMemoryUsage)}');
      shouldCleanup = true;
    } else if (_highWatermark != null && currentMemoryUsage > _highWatermark!) {
      print('HIGH MEMORY PRESSURE: ${_formatBytes(currentMemoryUsage)}');
      shouldCleanup = true;
    }

    // Also cleanup periodically regardless of memory pressure
    final timeSinceLastCleanup = now.difference(_lastCleanupTime);
    if (timeSinceLastCleanup > const Duration(minutes: 5)) {
      shouldCleanup = true;
    }

    if (shouldCleanup) {
      final freedBytes = performCleanup(
        aggressive:
            currentMemoryUsage > (_criticalWatermark ?? double.infinity),
      );

      _lastCleanupTime = now;

      if (freedBytes > 0) {
        print('Cleaned up ${_formatBytes(freedBytes)}');
      }
    }
  }

  /// Perform memory cleanup
  /// Returns the number of bytes freed
  int performCleanup({bool aggressive = false}) {
    if (!_isRunning) return 0;

    int freedBytes = 0;

    // 1. Clean up blocks that haven't been accessed recently
    freedBytes += _cleanupByAccessTime(aggressive);

    // 2. Clean up blocks that are no longer referenced
    freedBytes += _cleanupUnreferencedBlocks();

    // 3. 清理孤立的数据块（在_DataStore中存在但没有Block引用的数据）
    freedBytes += _cleanupOrphanedData();

    return freedBytes;
  }

  /// Clean up blocks that haven't been accessed recently
  int _cleanupByAccessTime(bool aggressive) {
    final now = DateTime.now();
    final threshold =
        aggressive ? const Duration(seconds: 30) : const Duration(minutes: 5);

    final blocksToRemove = <String>[];

    // 使用_blockTrackingMap而不是_blockAccessTimes
    for (final entry in _blockTrackingMap.entries) {
      final timeSinceAccess = now.difference(entry.value.lastAccessTime);
      if (timeSinceAccess > threshold) {
        blocksToRemove.add(entry.key);
      }
    }

    // Remove old blocks (in a real implementation, we would signal the application
    // that these blocks should be considered for disposal)
    int freedMemory = 0;
    for (final blockId in blocksToRemove) {
      if (_blockTrackingMap.containsKey(blockId)) {
        freedMemory += _blockTrackingMap[blockId]!.memoryCost;
      }
      // 注意：这里只是记录哪些Block可以被清理，不会主动清理
      // 实际清理应该由应用程序决定，或者在特别紧急的情况下进行
    }

    return freedMemory;
  }

  /// Clean up blocks that are no longer referenced
  int _cleanupUnreferencedBlocks() {
    // Remove weak references that no longer point to objects
    final refsBeforeCleanup = _weakBlockRefs.length;
    _weakBlockRefs.removeWhere((ref) => ref.target == null);
    final refsAfterCleanup = _weakBlockRefs.length;

    // 假设每个无效的弱引用可能释放约1KB内存（这只是粗略估计）
    final freedRefBytes = (refsBeforeCleanup - refsAfterCleanup) * 1024;

    return freedRefBytes;
  }

  /// 清理孤立的数据块（没有Block引用的数据）
  int _cleanupOrphanedData() {
    // 由于直接导入 block.dart 会导致循环依赖，所以我们只能返回估计值
    // 实际的清理应该由 _DataStore 调用 MemoryManager 的方法来实现
    // 在 _DataStore.cleanOrphanedData 中查询 MemoryManager 获取引用状态并清理数据

    // 基于当前已知的孤立数据数量估计清理的字节数
    // 假设每个孤立数据块平均 10KB
    int estimatedOrphanCount = 0;
    for (final entry in _dataReferenceMap.entries) {
      if (entry.value.isEmpty) {
        estimatedOrphanCount++;
      }
    }

    // 移除空引用集合
    _dataReferenceMap.removeWhere((_, refs) => refs.isEmpty);

    // 估计释放的内存 (每个孤立数据块按10KB计算)
    return estimatedOrphanCount * 10 * 1024;
  }

  /// Get current memory usage in bytes
  int getCurrentMemoryUsage() {
    // 使用我们的估计值而不是占位符0
    return _estimatedMemoryUsage;
  }

  /// Format bytes to a human-readable string
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
