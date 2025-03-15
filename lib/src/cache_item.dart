// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'cache_priority.dart';

/// 缓存项
class CacheItem<T> {
  /// 数据
  final T data;

  /// 内存消耗（字节）
  final int memoryCost;

  /// 优先级
  final CachePriority priority;

  /// 最后访问时间
  DateTime lastAccessed;

  /// 构造函数
  CacheItem({
    required this.data,
    required this.memoryCost,
    this.priority = CachePriority.medium,
  }) : lastAccessed = DateTime.now();

  /// 更新最后访问时间
  void touch() {
    lastAccessed = DateTime.now();
  }
}
