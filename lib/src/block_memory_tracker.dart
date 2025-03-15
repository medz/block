// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

/// 用于跟踪Block内存使用的辅助类
class BlockMemoryTracker {
  /// 内存成本
  final int memoryCost;

  /// 需要释放的数据块引用
  final List<Uint8List> dataToRelease;

  BlockMemoryTracker(this.memoryCost, this.dataToRelease);
}
