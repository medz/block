// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A dart library for efficiently handling binary data across platforms.
///
/// The Block library provides a pure Dart implementation of a Blob-like API.
/// It's designed to handle binary data efficiently on all platforms.
library block;

export 'src/block.dart' show Block, ByteDataView, MemoryPressureLevel;
export 'src/deferred_operation.dart'
    show
        DeferredOperation,
        DeferredOperations,
        DeferredTextDecoding,
        DeferredBlockMerge,
        DeferredDataTransformation;
