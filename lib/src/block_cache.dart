// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'cache_item.dart';
import 'cache_priority.dart';
import 'memory_pressure_level.dart';

/// 缓存池管理类
class BlockCache {
  /// 单例实例
  static final BlockCache _instance = BlockCache._();

  /// 获取单例实例
  static BlockCache get instance => _instance;

  /// 私有构造函数
  BlockCache._();

  /// 缓存池，按照Key存储缓存项
  final Map<String, CacheItem> _cache = {};

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
    CachePriority priority = CachePriority.medium,
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
    final item = CacheItem<T>(
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
  bool _isExpired(CacheItem item) {
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
        freedBytes = _clearByPriority(CachePriority.low);
        break;
      case MemoryPressureLevel.medium:
        // 中度压力：清理低优先级和中优先级缓存
        freedBytes = _clearByPriority(CachePriority.low);
        freedBytes += _clearByPriority(CachePriority.medium);
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
  int _clearByPriority(CachePriority priority) {
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
        if (entry.value.priority == CachePriority.high &&
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
