// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:core';

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
    // Add weak reference to the block
    _weakBlockRefs.add(WeakReference<Object>(block));

    // Record access time
    _recordBlockAccess(blockId);
  }

  /// Record that a block was accessed
  void recordBlockAccess(String blockId) {
    if (!_isRunning) return;
    _recordBlockAccess(blockId);
  }

  /// Internal method to record block access time
  void _recordBlockAccess(String blockId) {
    _blockAccessTimes[blockId] = DateTime.now();
  }

  /// Check if a block is still referenced
  bool isBlockReferenced(String blockId) {
    // This is a placeholder. In a real implementation, we would check
    // if any of the weak references still point to a block with this ID.
    return _blockAccessTimes.containsKey(blockId);
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

    return freedBytes;
  }

  /// Clean up blocks that haven't been accessed recently
  int _cleanupByAccessTime(bool aggressive) {
    final now = DateTime.now();
    final threshold =
        aggressive ? const Duration(seconds: 30) : const Duration(minutes: 5);

    final blocksToRemove = <String>[];

    // Find old blocks
    for (final entry in _blockAccessTimes.entries) {
      final timeSinceAccess = now.difference(entry.value);
      if (timeSinceAccess > threshold) {
        blocksToRemove.add(entry.key);
      }
    }

    // Remove old blocks
    for (final blockId in blocksToRemove) {
      _blockAccessTimes.remove(blockId);
    }

    // In a real implementation, we would actually free the memory
    // associated with these blocks. This is just a placeholder.
    return blocksToRemove.length * 1024; // Assume 1KB per block
  }

  /// Clean up blocks that are no longer referenced
  int _cleanupUnreferencedBlocks() {
    // Remove weak references that no longer point to objects
    _weakBlockRefs.removeWhere((ref) => ref.target == null);

    // In a real implementation, we would actually free the memory
    // associated with these blocks. This is just a placeholder.
    return 0;
  }

  /// Get current memory usage in bytes
  int getCurrentMemoryUsage() {
    // This is a placeholder. In a real implementation, we would
    // get the actual memory usage from the Block library.
    return 0;
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
