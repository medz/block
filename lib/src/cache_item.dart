// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'cache_priority.dart';

/// 缓存项
class CacheItem<T> {
  /// 缓存的数据
  final T data;

  /// 缓存项的内存占用（字节）
  final int memoryCost;

  /// 缓存项的优先级
  final CachePriority priority;

  /// 最后访问时间
  DateTime lastAccessed = DateTime.now();

  /// 创建时间
  final DateTime createdAt = DateTime.now();

  CacheItem({
    required this.data,
    required this.memoryCost,
    this.priority = CachePriority.medium,
  });

  /// 更新最后访问时间
  void touch() {
    lastAccessed = DateTime.now();
  }
}
