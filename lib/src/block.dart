import 'dart:typed_data';

import 'platform/block_factory.dart' as platform;

/// An immutable, Blob-like binary data container.
abstract interface class Block {
  /// Default stream chunk size (64KB).
  static const int defaultStreamChunkSize = 64 * 1024;

  /// Creates a block from Blob-compatible parts.
  ///
  /// Supported part types:
  /// - [String]
  /// - [Uint8List]
  /// - [ByteData]
  /// - [Block]
  factory Block(List<Object> parts, {String type = ''}) =>
      platform.createBlock(parts, type: type);

  /// The size in bytes.
  int get size;

  /// The media type.
  String get type;

  /// Returns a new [Block] containing bytes from [start] (inclusive)
  /// to [end] (exclusive), using Blob-compatible index normalization.
  Block slice(int start, [int? end, String? contentType]);

  /// Returns all bytes.
  Future<Uint8List> arrayBuffer();

  /// Returns UTF-8 decoded text.
  Future<String> text();

  /// Streams bytes in chunks.
  Stream<Uint8List> stream({int chunkSize = defaultStreamChunkSize});
}
