import 'dart:math';
import 'dart:typed_data';

final class SliceBounds {
  const SliceBounds(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}

SliceBounds normalizeSliceBounds(int size, int start, int? end) {
  var normalizedStart = start;
  var normalizedEnd = end ?? size;

  if (normalizedStart < 0) {
    normalizedStart += size;
  }

  if (normalizedEnd < 0) {
    normalizedEnd += size;
  }

  normalizedStart = normalizedStart.clamp(0, size);
  normalizedEnd = normalizedEnd.clamp(0, size);

  if (normalizedEnd < normalizedStart) {
    normalizedEnd = normalizedStart;
  }

  return SliceBounds(normalizedStart, normalizedEnd);
}

void validateChunkSize(int chunkSize) {
  if (chunkSize <= 0) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be greater than 0');
  }
}

Stream<Uint8List> chunkedBytes(
  Uint8List bytes, {
  required int chunkSize,
}) async* {
  validateChunkSize(chunkSize);
  if (bytes.isEmpty) {
    return;
  }

  var offset = 0;
  while (offset < bytes.length) {
    final next = min(offset + chunkSize, bytes.length);
    yield Uint8List.sublistView(bytes, offset, next);
    offset = next;
  }
}
