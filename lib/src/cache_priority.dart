// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// 缓存优先级枚举
enum CachePriority {
  /// 低优先级，在内存压力下最先被清理
  low,

  /// 中优先级，在中度内存压力下被清理
  medium,

  /// 高优先级，只有在高内存压力下才会被清理
  high,
}
