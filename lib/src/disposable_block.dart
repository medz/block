// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:block/block.dart';

// ByteDataView 已经通过 package:block/block.dart 导出，无需单独导入
// import 'byte_data_view.dart';

/// A disposable extension of Block that provides explicit memory management.
///
/// This class wraps a standard Block and adds the ability to explicitly
/// dispose of the block when it's no longer needed, helping to reduce
/// memory pressure in long-running applications.
class DisposableBlock {
  /// The underlying Block object
  Block? _block;

  /// The unique ID for this block
  final String _id;

  /// Whether this block has been disposed
  bool _isDisposed = false;

  /// Create a new DisposableBlock from a list of data chunks
  DisposableBlock(List<Uint8List> chunks)
    : _block = Block(chunks),
      _id = _generateId() {
    // Register with memory manager
    MemoryManager.instance.registerBlock(this, _id);
  }

  /// Create a new DisposableBlock wrapping an existing Block
  DisposableBlock.fromBlock(Block block) : _block = block, _id = _generateId() {
    // Register with memory manager
    MemoryManager.instance.registerBlock(this, _id);
  }

  /// Generate a unique ID for this block
  static String _generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${(identityHashCode(DateTime.now()) & 0xFFFFFF).toRadixString(16)}';
  }

  /// Get the size of the block in bytes
  int get size {
    _checkDisposed();
    MemoryManager.instance.recordBlockAccess(_id);
    return _block!.size;
  }

  /// Get a slice of the block
  DisposableBlock slice(int start, [int? end]) {
    _checkDisposed();
    MemoryManager.instance.recordBlockAccess(_id);
    final slicedBlock = _block!.slice(start, end);
    return DisposableBlock.fromBlock(slicedBlock);
  }

  /// Convert the block to a Uint8List
  ///
  /// This is a synchronous operation that returns the data immediately.
  /// For large blocks, consider using [arrayBuffer] instead.
  Uint8List toUint8List() {
    _checkDisposed();
    MemoryManager.instance.recordBlockAccess(_id);
    return _block!.getByteDataView().toUint8List();
  }

  /// Convert the block to a string
  Future<String> text() async {
    _checkDisposed();
    MemoryManager.instance.recordBlockAccess(_id);
    return await _block!.text();
  }

  /// Get the data as a Uint8List asynchronously
  ///
  /// This method corresponds to the Web API Blob.arrayBuffer() method.
  Future<Uint8List> arrayBuffer() async {
    _checkDisposed();
    MemoryManager.instance.recordBlockAccess(_id);
    return await _block!.arrayBuffer();
  }

  /// Get a stream of the block's data
  Stream<Uint8List> stream() {
    _checkDisposed();
    MemoryManager.instance.recordBlockAccess(_id);
    return _block!.stream();
  }

  /// Get a ByteDataView for direct access to the block's data
  ByteDataView getByteDataView() {
    _checkDisposed();
    MemoryManager.instance.recordBlockAccess(_id);
    return _block!.getByteDataView();
  }

  /// Explicitly dispose of this block to free memory
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;
    _block = null;

    // In a real implementation, we would notify the memory manager
    // that this block has been disposed, so it can update its tracking
    // and potentially free memory.
  }

  /// Check if the block has been disposed and throw if it has
  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot use a disposed block');
    }
  }

  /// Get a memory report for this block
  Map<String, dynamic> getMemoryReport() {
    _checkDisposed();
    return _block!.getMemoryReport();
  }

  @override
  String toString() {
    if (_isDisposed) {
      return 'DisposableBlock(disposed)';
    }
    return 'DisposableBlock(size: ${_block!.size} bytes)';
  }
}
