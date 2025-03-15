// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// 性能优化说明:
// 本实现参考了WebKit中Blob的实现，采用了多种策略避免不必要的数据复制:
// 1. 分片操作(slice)采用引用原始数据的方式，不复制数据，只保存引用和范围信息
// 2. 多层嵌套分片会被扁平化，避免链式引用导致的性能问题
// 3. 数据读取操作尽可能避免复制，使用sublist等方法直接引用原始数据
// 4. 流式读取针对分片进行了优化，只读取必要的数据段

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// A Block object represents an immutable, raw data file-like object.
///
/// This is a pure Dart implementation inspired by the Web API Blob.
/// It provides a way to handle binary data in Dart that works across all platforms.
class Block {
  /// The internal storage of data chunks
  final List<Uint8List> _chunks;

  /// Total size of all chunks in bytes
  final int _size;

  /// The MIME type of the Block
  final String _type;

  /// For slices: reference to the parent Block
  final Block? _parent;

  /// For slices: starting offset in the parent Block
  final int _startOffset;

  /// For slices: length of this slice in bytes
  final int _sliceLength;

  /// The default chunk size for segmented storage (1MB)
  static const int defaultChunkSize = 1024 * 1024;

  /// Creates a new Block consisting of an optional array of parts and a MIME type.
  ///
  /// This constructor exactly mirrors the Web API Blob constructor.
  ///
  /// The parts parameter can include:
  /// - String
  /// - Uint8List
  /// - ByteData
  /// - Block objects
  ///
  /// The type parameter specifies the MIME type of the Block.
  ///
  /// Example:
  /// ```dart
  /// // Create a Block from multiple parts
  /// final block = Block([
  ///   'Hello, ',
  ///   Uint8List.fromList(utf8.encode('world')),
  ///   '!'
  /// ], type: 'text/plain');
  ///
  /// // Create an empty Block
  /// final emptyBlock = Block([], type: 'application/octet-stream');
  /// ```
  Block(List<dynamic> parts, {String type = ''})
    : _chunks = _createBlockChunks(parts),
      _size = _calculateTotalSize(parts),
      _type = type,
      _parent = null,
      _startOffset = 0,
      _sliceLength = _calculateTotalSize(parts);

  /// Internal constructor for creating Block slices
  Block._slice(
    this._parent,
    this._startOffset,
    this._sliceLength, {
    required String type,
  }) : _chunks = [],
       _size = _sliceLength,
       _type = type;

  /// Internal constructor for creating Block from explicit chunks
  Block._fromChunks(this._chunks, this._size, this._type)
    : _parent = null,
      _startOffset = 0,
      _sliceLength = _size;

  /// Calculate the total size of all parts
  static int _calculateTotalSize(List<dynamic> parts) {
    if (parts.isEmpty) {
      return 0;
    }

    int totalSize = 0;
    for (final part in parts) {
      final Uint8List bytes = _convertPartToBytes(part);
      totalSize += bytes.length;
    }
    return totalSize;
  }

  /// Internal static method to create storage chunks from parts
  static List<Uint8List> _createBlockChunks(List<dynamic> parts) {
    if (parts.isEmpty) {
      return [];
    }

    final List<Uint8List> allBytes = [];
    for (final part in parts) {
      final Uint8List bytes = _convertPartToBytes(part);
      allBytes.add(bytes);
    }

    // Optimize for small data (< 1MB) by keeping it as a single chunk
    final int totalSize = allBytes.fold(0, (sum, bytes) => sum + bytes.length);
    if (totalSize <= defaultChunkSize && allBytes.length == 1) {
      return allBytes;
    }

    // For larger data or multiple parts, use segmented storage
    return _segmentDataIntoChunks(allBytes, totalSize);
  }

  /// Segment data into optimal chunks
  static List<Uint8List> _segmentDataIntoChunks(
    List<Uint8List> allBytes,
    int totalSize,
  ) {
    // If all parts are already small enough, just use them directly
    if (allBytes.every((bytes) => bytes.length <= defaultChunkSize)) {
      return List<Uint8List>.from(allBytes);
    }

    // Otherwise, reorganize into optimal chunk sizes
    final List<Uint8List> chunks = [];

    // First, handle very large individual parts by splitting them
    final List<Uint8List> normalizedParts = [];
    for (final bytes in allBytes) {
      if (bytes.length > defaultChunkSize) {
        // Split large parts into chunks
        int offset = 0;
        while (offset < bytes.length) {
          final int chunkSize =
              (offset + defaultChunkSize > bytes.length)
                  ? bytes.length - offset
                  : defaultChunkSize;

          final chunk = Uint8List(chunkSize);
          chunk.setRange(0, chunkSize, bytes, offset);
          normalizedParts.add(chunk);
          offset += chunkSize;
        }
      } else {
        normalizedParts.add(bytes);
      }
    }

    // Then optimize storage by combining small parts
    Uint8List? currentChunk;
    int currentSize = 0;

    for (final bytes in normalizedParts) {
      // If adding this part would exceed the chunk size, finalize current chunk
      if (currentChunk != null &&
          currentSize + bytes.length > defaultChunkSize) {
        chunks.add(currentChunk);
        currentChunk = null;
        currentSize = 0;
      }

      // Start a new chunk if needed
      if (currentChunk == null) {
        // If this part is exactly at chunk size, add it directly
        if (bytes.length == defaultChunkSize) {
          chunks.add(bytes);
          continue;
        }

        // Otherwise start a new chunk
        currentChunk = Uint8List(defaultChunkSize);
        currentSize = 0;
      }

      // Add bytes to the current chunk
      currentChunk.setRange(currentSize, currentSize + bytes.length, bytes);
      currentSize += bytes.length;

      // If chunk is full, finalize it
      if (currentSize == defaultChunkSize) {
        chunks.add(currentChunk);
        currentChunk = null;
        currentSize = 0;
      }
    }

    // Add any remaining data
    if (currentChunk != null && currentSize > 0) {
      // Create right-sized final chunk
      final finalChunk = Uint8List(currentSize);
      finalChunk.setRange(0, currentSize, currentChunk, 0);
      chunks.add(finalChunk);
    }

    return chunks;
  }

  /// Helper function to convert various types to Uint8List
  static Uint8List _convertPartToBytes(dynamic part) {
    if (part is String) {
      return Uint8List.fromList(utf8.encode(part));
    } else if (part is Uint8List) {
      return part;
    } else if (part is ByteData) {
      return Uint8List.view(
        part.buffer,
        part.offsetInBytes,
        part.lengthInBytes,
      );
    } else if (part is Block) {
      // If it's already a Block, get its data
      // For a direct Block, we need to combine chunks
      if (part._parent == null && part._chunks.isNotEmpty) {
        if (part._chunks.length == 1) {
          return part._chunks[0];
        } else {
          return part._combineChunks();
        }
      }
      // For a slice, we need to get the slice data
      else if (part._parent != null) {
        final parentData = part._parent!._combineChunks();
        final sliceData = Uint8List(part._sliceLength);
        sliceData.setRange(0, part._sliceLength, parentData, part._startOffset);
        return sliceData;
      } else {
        // Empty Block
        return Uint8List(0);
      }
    } else {
      throw ArgumentError(
        'Unsupported part type: ${part.runtimeType}. '
        'Supported types are String, Uint8List, ByteData, and Block.',
      );
    }
  }

  /// Combines all chunks into a single Uint8List
  Uint8List _combineChunks() {
    // Handle parent slice
    if (_parent != null) {
      // 优化: 避免不必要的完整父数据复制
      // 如果父级是分片，直接从顶级父对象中获取数据，避免中间复制
      if (_parent!._parent != null) {
        return _parent!._parent!._combineChunks().sublist(
          _parent!._startOffset + _startOffset,
          _parent!._startOffset + _startOffset + _sliceLength,
        );
      }

      // 如果父级是直接对象，按原来方式处理
      final parentData = _parent!._combineChunks();
      // 直接使用sublist而不是创建新数组并复制数据
      return parentData.sublist(_startOffset, _startOffset + _sliceLength);
    }

    // Handle empty block
    if (_chunks.isEmpty || _size == 0) {
      return Uint8List(0);
    }

    // Handle single chunk case (optimization)
    if (_chunks.length == 1 && _chunks[0].length == _size) {
      return _chunks[0];
    }

    // Handle multiple chunks case
    final result = Uint8List(_size);
    int offset = 0;

    for (final chunk in _chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }

  /// Returns the size of the Block in bytes.
  int get size => _size;

  /// Returns the MIME type of the Block.
  String get type => _type;

  /// Returns a new Block object containing the data in the specified range.
  ///
  /// This method exactly mirrors the Web API Blob.slice() method.
  ///
  /// [start] - An index indicating the first byte to include in the new Block.
  /// [end] - An index indicating the first byte that will not be included in the new Block.
  /// [contentType] - The content type of the new Block, or an empty string if not specified.
  ///
  /// Example:
  /// ```dart
  /// final slice = block.slice(10, 20, 'text/plain');
  /// ```
  Block slice(int start, [int? end, String? contentType]) {
    // Handle negative indices
    final int dataSize = _size;

    if (start < 0) start = dataSize + start;
    final int normalizedEnd =
        (end != null && end < 0) ? dataSize + end : (end ?? dataSize);

    // Clamp to valid range
    start = start.clamp(0, dataSize);
    final int endOffset = normalizedEnd.clamp(0, dataSize);

    if (start >= endOffset) {
      return Block([], type: contentType ?? _type);
    }

    final sliceLength = endOffset - start;

    // 优化: 避免过深的slice嵌套
    // 如果这已经是一个slice，寻找根Block以避免多层slice嵌套
    if (_parent != null) {
      // 找到根Block
      Block rootParent = _parent!;
      int totalOffset = _startOffset + start;

      while (rootParent._parent != null) {
        totalOffset += rootParent._startOffset;
        rootParent = rootParent._parent!;
      }

      // 从根Block创建slice，避免多层嵌套
      return Block._slice(
        rootParent,
        totalOffset,
        sliceLength,
        type: contentType ?? _type,
      );
    }

    // Otherwise create a slice of this Block
    return Block._slice(this, start, sliceLength, type: contentType ?? _type);
  }

  /// Returns a Promise that resolves with a Uint8List containing the entire contents of the Block.
  ///
  /// This method corresponds to the Web API Blob.arrayBuffer() method.
  ///
  /// Example:
  /// ```dart
  /// final data = await block.arrayBuffer();
  /// ```
  Future<Uint8List> arrayBuffer() async {
    // 避免在异步操作中不必要的数据复制
    return Future.value(_combineChunks());
  }

  /// Returns a Promise that resolves with a string containing the entire contents of the Block.
  ///
  /// This method corresponds to the Web API Blob.text() method.
  ///
  /// Example:
  /// ```dart
  /// final text = await block.text();
  /// ```
  Future<String> text({Encoding encoding = utf8}) async {
    return encoding.decode(await arrayBuffer());
  }

  /// Streams the Block's data in chunks.
  ///
  /// This is a Dart-specific addition that doesn't exist in the Web API Blob,
  /// but is useful for handling large data efficiently.
  ///
  /// The [chunkSize] parameter controls the size of each chunk.
  ///
  /// Example:
  /// ```dart
  /// await for (final chunk in block.stream(chunkSize: 1024)) {
  ///   // Process chunk
  /// }
  /// ```
  Stream<Uint8List> stream({int chunkSize = 1024 * 64}) async* {
    // For a slice, get data from parent
    if (_parent != null) {
      // 优化: 避免读取整个父Block的数据
      // 如果父Block很大但slice很小，这可以节省大量内存

      // 当父Block是分段存储时直接访问相关段
      if (_parent!._chunks.isNotEmpty) {
        int remainingBytes = _sliceLength;
        int globalOffset = _startOffset;

        // 找出包含起始位置的chunk
        int currentChunkIndex = 0;
        int accumulatedSize = 0;

        // 找到包含起始位置的chunk
        while (currentChunkIndex < _parent!._chunks.length) {
          final chunkSize = _parent!._chunks[currentChunkIndex].length;
          if (accumulatedSize + chunkSize > globalOffset) {
            break;
          }
          accumulatedSize += chunkSize;
          currentChunkIndex++;
        }

        // 如果找不到合适的chunk（可能是空Block），直接返回
        if (currentChunkIndex >= _parent!._chunks.length) {
          return;
        }

        // 计算在当前chunk中的偏移量
        int offsetInCurrentChunk = globalOffset - accumulatedSize;

        // 开始流式传输数据
        while (remainingBytes > 0 &&
            currentChunkIndex < _parent!._chunks.length) {
          final currentChunk = _parent!._chunks[currentChunkIndex];
          final bytesLeftInChunk = currentChunk.length - offsetInCurrentChunk;

          // 确定此次要读取的字节数
          final bytesToRead =
              bytesLeftInChunk < remainingBytes
                  ? bytesLeftInChunk
                  : remainingBytes < chunkSize
                  ? remainingBytes
                  : chunkSize;

          // 直接使用sublist避免复制
          if (offsetInCurrentChunk == 0 && bytesToRead == currentChunk.length) {
            yield currentChunk;
          } else {
            yield currentChunk.sublist(
              offsetInCurrentChunk,
              offsetInCurrentChunk + bytesToRead,
            );
          }

          remainingBytes -= bytesToRead;

          // 移动到下一个chunk
          if (bytesToRead >= bytesLeftInChunk) {
            currentChunkIndex++;
            offsetInCurrentChunk = 0;
          } else {
            offsetInCurrentChunk += bytesToRead;
          }
        }
        return;
      }
      // 当父Block是嵌套slice时，让父Block处理
      else if (_parent!._parent != null) {
        // 创建一个新的合并计算的slice直接从顶层读取
        final combinedSlice = _parent!.slice(
          _startOffset,
          _startOffset + _sliceLength,
        );
        await for (final chunk in combinedSlice.stream(chunkSize: chunkSize)) {
          yield chunk;
        }
        return;
      }
      // 如果父级结构复杂，回退到原始实现
      else {
        final parentData = await _parent!.arrayBuffer();
        int offset = _startOffset;
        final int end = _startOffset + _sliceLength;

        while (offset < end) {
          final int remainingBytes = end - offset;
          final int bytesToRead =
              remainingBytes < chunkSize ? remainingBytes : chunkSize;

          // 使用sublist避免复制
          yield parentData.sublist(offset, offset + bytesToRead);

          offset += bytesToRead;
        }
        return;
      }
    }

    // For empty block
    if (_chunks.isEmpty || _size == 0) {
      return;
    }

    // For small data that fits in one chunk, optimize by yielding directly
    if (_size <= chunkSize && _chunks.length == 1) {
      yield _chunks[0];
      return;
    }

    // For data with multiple chunks, yield by copying across chunk boundaries
    int globalOffset = 0;
    int currentChunkIndex = 0;
    int offsetInCurrentChunk = 0;

    while (globalOffset < _size) {
      final currentChunk = _chunks[currentChunkIndex];
      final bytesLeftInChunk = currentChunk.length - offsetInCurrentChunk;

      // If we can get a full chunk size from current chunk
      if (bytesLeftInChunk >= chunkSize) {
        final chunk = Uint8List(chunkSize);
        chunk.setRange(0, chunkSize, currentChunk, offsetInCurrentChunk);
        yield chunk;

        offsetInCurrentChunk += chunkSize;
        globalOffset += chunkSize;

        // Move to next chunk if needed
        if (offsetInCurrentChunk >= currentChunk.length) {
          currentChunkIndex++;
          offsetInCurrentChunk = 0;
        }
      }
      // If we need to combine data from multiple chunks
      else {
        final int bytesToRead =
            _size - globalOffset < chunkSize ? _size - globalOffset : chunkSize;
        final chunk = Uint8List(bytesToRead);

        int chunkOffset = 0;
        int bytesRemaining = bytesToRead;

        while (bytesRemaining > 0) {
          final currentChunk = _chunks[currentChunkIndex];
          final bytesToCopy =
              bytesLeftInChunk < bytesRemaining
                  ? bytesLeftInChunk
                  : bytesRemaining;

          chunk.setRange(
            chunkOffset,
            chunkOffset + bytesToCopy,
            currentChunk,
            offsetInCurrentChunk,
          );

          chunkOffset += bytesToCopy;
          bytesRemaining -= bytesToCopy;
          globalOffset += bytesToCopy;

          offsetInCurrentChunk += bytesToCopy;
          if (offsetInCurrentChunk >= currentChunk.length &&
              bytesRemaining > 0) {
            currentChunkIndex++;
            offsetInCurrentChunk = 0;
          }
        }

        yield chunk;
      }
    }
  }

  /// Convenience static method to create an empty Block.
  ///
  /// Example:
  /// ```dart
  /// final emptyBlock = Block.empty(type: 'text/plain');
  /// ```
  static Block empty({String type = ''}) {
    return Block([], type: type);
  }
}
