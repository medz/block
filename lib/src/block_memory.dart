import 'dart:convert';
import 'dart:typed_data';

import 'block.dart';
import 'block_base.dart';
import 'utils.dart';

final class MemoryBlock extends BlockBase {
  MemoryBlock._(this._bytes, this._type);

  static const int defaultThreshold = 64 * 1024;

  factory MemoryBlock.fromBytes(Uint8List bytes, {String type = ''}) {
    return MemoryBlock._(bytes, type);
  }

  static MemoryBlock? tryFromParts(
    List<Object> parts, {
    required String type,
    int threshold = defaultThreshold,
  }) {
    if (parts.isEmpty) {
      return MemoryBlock._(Uint8List(0), type);
    }

    final chunks = <Uint8List>[];
    var total = 0;

    for (final part in parts) {
      final bytes = _bytesForPart(part);
      if (bytes == null) {
        return null;
      }
      if (bytes.isEmpty) {
        continue;
      }

      total += bytes.length;
      if (total > threshold) {
        return null;
      }
      chunks.add(bytes);
    }

    if (chunks.isEmpty) {
      return MemoryBlock._(Uint8List(0), type);
    }

    if (chunks.length == 1) {
      return MemoryBlock._(chunks.first, type);
    }

    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      builder.add(chunk);
    }
    return MemoryBlock._(builder.takeBytes(), type);
  }

  static Uint8List? _bytesForPart(Object part) {
    if (part is String) {
      return utf8.encode(part);
    }

    if (part is Uint8List) {
      return part;
    }

    if (part is ByteData) {
      return part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes);
    }

    if (part is MemoryBlock) {
      return part._bytes;
    }

    return null;
  }

  final Uint8List _bytes;
  final String _type;

  Uint8List copyBytesSync() => _bytes;

  @override
  int get size => _bytes.length;

  @override
  String get type => _type;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final bounds = normalizeSliceBounds(_bytes.length, start, end);
    final sliced = Uint8List.sublistView(_bytes, bounds.start, bounds.end);
    return MemoryBlock._(sliced, contentType ?? '');
  }

  @override
  Future<Uint8List> arrayBuffer() async => _bytes;
}
