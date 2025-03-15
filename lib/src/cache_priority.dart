// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// 缓存项的优先级
enum CachePriority {
  /// 高优先级缓存，仅在高内存压力下清理
  high,

  /// 中优先级缓存，在中度内存压力下清理
  medium,

  /// 低优先级缓存，在轻度内存压力下清理
  low,
}
