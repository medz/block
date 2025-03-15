// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
