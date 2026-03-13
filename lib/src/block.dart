import 'dart:typed_data';

import 'block_stub.dart'
    if (dart.library.io) 'block_file.dart'
    if (dart.library.js_interop) 'block_web.dart'
    as platform;

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
  /// - `dart:io File` on IO platforms
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
  ///
  /// This materializes the full block in memory.
  Future<Uint8List> arrayBuffer();

  /// Returns UTF-8 decoded text.
  Future<String> text();

  /// Streams bytes in chunks.
  ///
  /// This is the primary lazy read path for downstream integrators that want
  /// to preserve streaming behavior.
  Stream<Uint8List> stream({int chunkSize = defaultStreamChunkSize});
}
