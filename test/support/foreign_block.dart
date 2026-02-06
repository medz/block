import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:block/block.dart';

final class ForeignBlock implements Block {
  ForeignBlock(Uint8List bytes, {this.type = ''})
    : _bytes = Uint8List.fromList(bytes);

  factory ForeignBlock.fromText(String text, {String type = ''}) {
    return ForeignBlock(_utf8Bytes(text), type: type);
  }

  final Uint8List _bytes;

  @override
  final String type;

  @override
  int get size => _bytes.length;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final bounds = _normalizeSliceBounds(_bytes.length, start, end);
    final next = Uint8List.fromList(_bytes.sublist(bounds.start, bounds.end));
    return ForeignBlock(next, type: contentType ?? '');
  }

  @override
  Future<Uint8List> arrayBuffer() async => Uint8List.fromList(_bytes);

  @override
  Future<String> text() async => utf8.decode(_bytes);

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    if (chunkSize <= 0) {
      throw ArgumentError.value(
        chunkSize,
        'chunkSize',
        'must be greater than 0',
      );
    }

    var offset = 0;
    while (offset < _bytes.length) {
      final next = min(offset + chunkSize, _bytes.length);
      yield Uint8List.fromList(_bytes.sublist(offset, next));
      offset = next;
    }
  }
}

({int start, int end, int length}) _normalizeSliceBounds(
  int size,
  int start,
  int? end,
) {
  final normalizedStart = _normalizeBoundary(size, start);
  final normalizedEnd = _normalizeBoundary(size, end ?? size);
  final clampedEnd = normalizedEnd < normalizedStart
      ? normalizedStart
      : normalizedEnd;

  return (
    start: normalizedStart,
    end: clampedEnd,
    length: clampedEnd - normalizedStart,
  );
}

int _normalizeBoundary(int size, int value) {
  if (value < 0) {
    return max(size + value, 0);
  }
  return min(value, size);
}

Uint8List _utf8Bytes(String value) {
  return utf8.encode(value);
}
