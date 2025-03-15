// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

/// 共享数据结构，包含数据和引用计数
class SharedData {
  /// 数据内容
  final Uint8List data;

  /// 引用计数
  int refCount;

  SharedData(this.data, this.refCount);
}
