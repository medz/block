// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// 内存压力级别枚举
enum MemoryPressureLevel {
  /// 无内存压力
  none,

  /// 低内存压力
  low,

  /// 中度内存压力
  medium,

  /// 高内存压力
  high,

  /// 危险级别内存压力
  critical,
}
