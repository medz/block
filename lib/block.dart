// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Block库提供了高效的二进制数据处理功能，类似于Web API中的Blob。
///
/// 主要特性:
/// - 高效的内存管理和数据分片
/// - 数据去重以优化内存使用
/// - 流式数据处理
/// - 异步API支持
/// - 零拷贝数据访问
library;

export 'src/block.dart';
export 'src/block_cache.dart';
export 'src/byte_data_view.dart';
export 'src/cache_item.dart';
export 'src/cache_priority.dart';
export 'src/data_store.dart' hide BlockCache;
export 'src/deferred_operation.dart';
export 'src/memory_manager.dart';
export 'src/disposable_block.dart';
export 'src/shared_data.dart';
export 'src/block_memory_tracker.dart';
export 'src/memory_pressure_level.dart';
