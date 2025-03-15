// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

/// 表示对原始二进制数据的视图，无需复制数据
///
/// 这个类允许在不复制数据的情况下访问底层二进制数据，
/// 提供了类似于ByteData的接口，但保留了对原始数据的引用。
class ByteDataView {
  /// 对原始数据的引用
  final List<Uint8List> _chunks;

  /// 数据的总长度
  final int length;

  /// 如果是分片，则表示起始偏移量
  final int _offset;

  /// 父视图（如果这是一个子视图）
  final ByteDataView? _parent;

  /// 创建一个新的数据视图
  ///
  /// [chunks] 是底层数据块的列表
  /// [length] 是数据的总长度
  ByteDataView(this._chunks, this.length) : _offset = 0, _parent = null;

  /// 创建一个子视图
  ///
  /// [parent] 是父视图
  /// [offset] 是在父视图中的起始位置
  /// [length] 是子视图的长度
  ByteDataView._(this._parent, this._offset, this.length) : _chunks = [];

  /// 创建一个子视图，表示原始数据的一部分，无需复制
  ByteDataView subView(int start, [int? end]) {
    final int endOffset = end ?? length;

    if (start < 0) start = 0;
    if (endOffset > length) throw RangeError('End offset exceeds view length');
    if (start >= endOffset) return ByteDataView([], 0);

    return ByteDataView._(this, start, endOffset - start);
  }

  /// 获取指定位置的字节
  int getUint8(int byteOffset) {
    if (byteOffset < 0 || byteOffset >= length) {
      throw RangeError('Offset out of range');
    }

    if (_parent != null) {
      return _parent.getUint8(_offset + byteOffset);
    }

    // 定位到正确的块
    int currentOffset = 0;
    for (final chunk in _chunks) {
      if (byteOffset < currentOffset + chunk.length) {
        return chunk[byteOffset - currentOffset];
      }
      currentOffset += chunk.length;
    }

    throw StateError('Unable to locate byte at offset $byteOffset');
  }

  /// 将数据复制到目标缓冲区
  void copyTo(Uint8List target, [int targetOffset = 0]) {
    if (targetOffset < 0) {
      throw RangeError('Target offset out of range');
    }

    if (targetOffset + length > target.length) {
      throw RangeError('Target buffer too small');
    }

    if (_parent != null) {
      _parent._copyRange(target, targetOffset, _offset, _offset + length);
      return;
    }

    _copyRange(target, targetOffset, 0, length);
  }

  /// 内部方法：将指定范围的数据复制到目标缓冲区
  void _copyRange(Uint8List target, int targetOffset, int start, int end) {
    if (_parent != null) {
      _parent._copyRange(target, targetOffset, _offset + start, _offset + end);
      return;
    }

    int sourceOffset = 0;
    int currentTargetOffset = targetOffset;
    int remainingBytes = end - start;

    // 跳过start之前的块
    for (final chunk in _chunks) {
      if (sourceOffset + chunk.length <= start) {
        sourceOffset += chunk.length;
        continue;
      }

      // 计算此块中的起始位置和复制长度
      final int chunkStart = start > sourceOffset ? start - sourceOffset : 0;
      final int bytesToCopy =
          (sourceOffset + chunk.length > end)
              ? remainingBytes
              : chunk.length - chunkStart;

      // 复制此块的数据
      target.setRange(
        currentTargetOffset,
        currentTargetOffset + bytesToCopy,
        chunk,
        chunkStart,
      );

      currentTargetOffset += bytesToCopy;
      remainingBytes -= bytesToCopy;

      if (remainingBytes <= 0) break;
      sourceOffset += chunk.length;
    }
  }

  /// 将视图转换为Uint8List，此操作会复制数据
  Uint8List toUint8List() {
    final result = Uint8List(length);
    copyTo(result);
    return result;
  }

  /// 检查此视图是否为单个连续的数据块
  bool get isContinuous => _parent == null && _chunks.length == 1;

  /// 如果视图是单个连续数据块，直接返回原始引用；否则返回null
  ///
  /// 使用此方法可以在某些情况下完全避免数据复制
  Uint8List? get continuousData {
    if (isContinuous) {
      return _chunks[0];
    }

    if (_parent != null &&
        _parent.isContinuous &&
        _offset == 0 &&
        length == _parent.length) {
      return _parent.continuousData;
    }

    return null;
  }

  /// 获取一个字节视图
  ByteBuffer get buffer => toUint8List().buffer;
}
