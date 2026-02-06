final class SliceBounds {
  SliceBounds(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}

SliceBounds normalizeSliceBounds(int size, int start, int? end) {
  var normalizedStart = start;
  var normalizedEnd = end ?? size;

  if (normalizedStart < 0) {
    normalizedStart = size + normalizedStart;
  }

  if (normalizedEnd < 0) {
    normalizedEnd = size + normalizedEnd;
  }

  normalizedStart = normalizedStart.clamp(0, size);
  normalizedEnd = normalizedEnd.clamp(0, size);

  if (normalizedEnd < normalizedStart) {
    normalizedEnd = normalizedStart;
  }

  return SliceBounds(normalizedStart, normalizedEnd);
}
