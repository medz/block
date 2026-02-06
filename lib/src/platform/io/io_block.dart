import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../block.dart';
import '../slice_bounds.dart';

const String ioTempFilePrefix = 'block_io_';
const int _sliceCopyThreshold = 64 * 1024;

Block createIoBlock(List<Object> parts, {String type = ''}) {
  return _IoComposedBlock._fromParts(parts, type: type);
}

Map<String, Object?> ioDebugMetadata(Block block) {
  if (block is _IoBlock) {
    return _debugMaterializedIoBlock(block);
  }

  if (block is _IoComposedBlock) {
    final materialized = block._materialized;
    if (materialized != null) {
      return _debugMaterializedIoBlock(
        materialized,
        reportedLength: block._length,
      );
    }

    return {
      'implementation': 'io',
      'backingPath': null,
      'backingIdentity': null,
      'offset': null,
      'length': block._length,
    };
  }

  if (block is _IoDeferredSliceBlock) {
    final resolved = block._resolved;
    if (resolved != null) {
      return _debugMaterializedIoBlock(resolved, reportedLength: block._length);
    }

    return {
      'implementation': 'io',
      'backingPath': null,
      'backingIdentity': null,
      'offset': null,
      'length': block._length,
    };
  }

  return const {
    'implementation': 'unknown',
    'backingPath': null,
    'backingIdentity': null,
    'offset': null,
    'length': null,
  };
}

Map<String, Object?> _debugMaterializedIoBlock(
  _IoBlock block, {
  int? reportedLength,
}) {
  return {
    'implementation': 'io',
    'backingPath': block._backing.file.path,
    'backingIdentity': identityHashCode(block._backing),
    'offset': block._offset,
    'length': reportedLength ?? block._length,
  };
}

final class _IoCleanupToken {
  _IoCleanupToken(this.path, this.handle);

  final String path;
  final RandomAccessFile handle;
}

final Finalizer<_IoCleanupToken> _ioFinalizer = Finalizer<_IoCleanupToken>((
  token,
) {
  try {
    token.handle.closeSync();
  } catch (error) {
    stderr.writeln('block: failed to close temp handle: $error');
  }

  try {
    final file = File(token.path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  } catch (error) {
    stderr.writeln('block: failed to delete temp file: $error');
  }
});

final class _IoBacking {
  _IoBacking._(this.file, this.handle, this.totalSize) {
    _ioFinalizer.attach(this, _IoCleanupToken(file.path, handle), detach: this);
  }

  static int _counter = 0;

  final File file;
  final RandomAccessFile handle;
  final int totalSize;

  static _IoBacking fromBytes(Uint8List bytes) {
    final path = _buildTempPath();
    final file = File(path);
    final handle = file.openSync(mode: FileMode.write);
    if (bytes.isNotEmpty) {
      handle.writeFromSync(bytes);
    }
    handle.setPositionSync(0);
    return _IoBacking._(file, handle, bytes.length);
  }

  static String _buildTempPath() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final nonce = (_counter++).toRadixString(16);
    final separator = Platform.pathSeparator;
    return '${Directory.systemTemp.path}$separator$ioTempFilePrefix${now}_$nonce.tmp';
  }

  Uint8List readRangeSync(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > totalSize) {
      throw RangeError.range(offset + length, 0, totalSize, 'offset/length');
    }

    if (length == 0) {
      return Uint8List(0);
    }

    handle.setPositionSync(offset);
    final bytes = handle.readSync(length);
    if (bytes.length != length) {
      throw StateError(
        'Unexpected end of file while reading $length bytes from ${file.path}.',
      );
    }

    return bytes;
  }
}

abstract interface class _IoReadable {
  int get size;

  Uint8List _readRangeSync(int offset, int length);
}

final class _IoBlock implements Block, _IoReadable {
  _IoBlock._(this._backing, this._offset, this._length, this._type);

  final _IoBacking _backing;
  final int _offset;
  final int _length;
  final String _type;

  @override
  int get size => _length;

  @override
  String get type => _type;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final bounds = normalizeSliceBounds(_length, start, end);
    final sliceLength = bounds.length;
    final nextType = contentType ?? '';

    if (sliceLength <= _sliceCopyThreshold) {
      final copied = _backing.readRangeSync(
        _offset + bounds.start,
        sliceLength,
      );
      final copiedBacking = _IoBacking.fromBytes(copied);
      return _IoBlock._(copiedBacking, 0, sliceLength, nextType);
    }

    return _IoBlock._(_backing, _offset + bounds.start, sliceLength, nextType);
  }

  @override
  Future<Uint8List> arrayBuffer() async => _readViewSync();

  @override
  Future<String> text() async => utf8.decode(_readViewSync());

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

    var readOffset = 0;
    while (readOffset < _length) {
      final toRead = min(chunkSize, _length - readOffset);
      yield _readRangeSync(readOffset, toRead);
      readOffset += toRead;
    }
  }

  Uint8List _readViewSync() => _readRangeSync(0, _length);

  @override
  Uint8List _readRangeSync(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > _length) {
      throw RangeError.range(offset + length, 0, _length, 'offset/length');
    }
    return _backing.readRangeSync(_offset + offset, length);
  }
}

abstract base class _IoCompositePart {
  int get length;

  Uint8List readRangeSync(int start, int length);

  Uint8List readBytesSync() => readRangeSync(0, length);
}

final class _IoBytesPart extends _IoCompositePart {
  _IoBytesPart(Uint8List bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Uint8List readRangeSync(int start, int length) {
    final end = start + length;
    if (start < 0 || length < 0 || end > _bytes.length) {
      throw RangeError.range(end, 0, _bytes.length, 'start/length');
    }
    return Uint8List.fromList(_bytes.sublist(start, end));
  }
}

final class _IoReadablePart extends _IoCompositePart {
  _IoReadablePart(this._source, this._sourceOffset, this.length);

  final _IoReadable _source;
  final int _sourceOffset;

  @override
  final int length;

  @override
  Uint8List readRangeSync(int start, int length) {
    final end = start + length;
    if (start < 0 || length < 0 || end > this.length) {
      throw RangeError.range(end, 0, this.length, 'start/length');
    }
    return _source._readRangeSync(_sourceOffset + start, length);
  }
}

final class _IoComposedBlock implements Block, _IoReadable {
  _IoComposedBlock._(this._parts, this._length, this._type);

  factory _IoComposedBlock._fromParts(List<Object> parts, {String type = ''}) {
    final normalized = _normalizeParts(parts);
    return _IoComposedBlock._(normalized.parts, normalized.totalSize, type);
  }

  final List<_IoCompositePart> _parts;
  final int _length;
  final String _type;
  _IoBlock? _materialized;

  @override
  int get size => _length;

  @override
  String get type => _type;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final materialized = _materialized;
    if (materialized != null) {
      return materialized.slice(start, end, contentType);
    }

    final bounds = normalizeSliceBounds(_length, start, end);
    final sliceLength = bounds.length;
    final nextType = contentType ?? '';
    return _IoDeferredSliceBlock._fromSource(
      this,
      bounds.start,
      sliceLength,
      nextType,
    );
  }

  @override
  Future<Uint8List> arrayBuffer() => _ensureMaterializedSync().arrayBuffer();

  @override
  Future<String> text() => _ensureMaterializedSync().text();

  @override
  Stream<Uint8List> stream({int chunkSize = Block.defaultStreamChunkSize}) {
    return _ensureMaterializedSync().stream(chunkSize: chunkSize);
  }

  @override
  Uint8List _readRangeSync(int offset, int length) {
    final materialized = _materialized;
    if (materialized != null) {
      return materialized._readRangeSync(offset, length);
    }
    return _readRangeFromPartsSync(offset, length);
  }

  _IoBlock _ensureMaterializedSync() {
    final existing = _materialized;
    if (existing != null) {
      return existing;
    }

    final merged = Uint8List(_length);
    var cursor = 0;
    for (final part in _parts) {
      final bytes = part.readBytesSync();
      merged.setRange(cursor, cursor + bytes.length, bytes);
      cursor += bytes.length;
    }

    final backing = _IoBacking.fromBytes(merged);
    final materialized = _IoBlock._(backing, 0, _length, _type);
    _materialized = materialized;
    return materialized;
  }

  Uint8List _readRangeFromPartsSync(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > _length) {
      throw RangeError.range(offset + length, 0, _length, 'offset/length');
    }
    if (length == 0) {
      return Uint8List(0);
    }

    final output = Uint8List(length);
    var outputCursor = 0;
    var remainingSkip = offset;
    var remainingLength = length;

    for (final part in _parts) {
      if (remainingLength == 0) {
        break;
      }

      if (remainingSkip >= part.length) {
        remainingSkip -= part.length;
        continue;
      }

      final localStart = remainingSkip;
      final available = part.length - localStart;
      final take = min(available, remainingLength);
      final segment = part.readRangeSync(localStart, take);
      output.setRange(outputCursor, outputCursor + take, segment);

      outputCursor += take;
      remainingLength -= take;
      remainingSkip = 0;
    }

    return output;
  }

  static ({List<_IoCompositePart> parts, int totalSize}) _normalizeParts(
    List<Object> parts,
  ) {
    if (parts.isEmpty) {
      return (parts: const <_IoCompositePart>[], totalSize: 0);
    }

    final normalized = <_IoCompositePart>[];
    var totalSize = 0;

    for (final part in parts) {
      final normalizedPart = _normalizePart(part);
      if (normalizedPart.length == 0) {
        continue;
      }
      normalized.add(normalizedPart);
      totalSize += normalizedPart.length;
    }

    return (
      parts: List<_IoCompositePart>.unmodifiable(normalized),
      totalSize: totalSize,
    );
  }

  static _IoCompositePart _normalizePart(Object part) {
    if (part is String) {
      return _IoBytesPart(Uint8List.fromList(utf8.encode(part)));
    }

    if (part is Uint8List) {
      return _IoBytesPart(Uint8List.fromList(part));
    }

    if (part is ByteData) {
      return _IoBytesPart(
        Uint8List.fromList(
          part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes),
        ),
      );
    }

    if (part is _IoReadable) {
      return _IoReadablePart(part, 0, part.size);
    }

    if (part is Block) {
      throw ArgumentError(
        'Unsupported Block implementation ${part.runtimeType} on io platform. '
        'Use Block instances created by this package on the same platform.',
      );
    }

    throw ArgumentError(
      'Unsupported part type: ${part.runtimeType}. '
      'Supported types are String, Uint8List, ByteData, and Block.',
    );
  }
}

final class _IoDeferredSliceBlock implements Block, _IoReadable {
  _IoDeferredSliceBlock._(
    this._source,
    this._sourceOffset,
    this._length,
    this._type,
  );

  factory _IoDeferredSliceBlock._fromSource(
    _IoReadable source,
    int sourceOffset,
    int length,
    String type,
  ) {
    var normalizedSource = source;
    var normalizedOffset = sourceOffset;
    while (normalizedSource is _IoDeferredSliceBlock) {
      normalizedOffset += normalizedSource._sourceOffset;
      normalizedSource = normalizedSource._source;
    }

    return _IoDeferredSliceBlock._(
      normalizedSource,
      normalizedOffset,
      length,
      type,
    );
  }

  final _IoReadable _source;
  final int _sourceOffset;
  final int _length;
  final String _type;
  _IoBlock? _resolved;

  @override
  int get size => _length;

  @override
  String get type => _type;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final resolved = _resolved;
    if (resolved != null) {
      return resolved.slice(start, end, contentType);
    }

    final bounds = normalizeSliceBounds(_length, start, end);
    return _IoDeferredSliceBlock._fromSource(
      _source,
      _sourceOffset + bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<Uint8List> arrayBuffer() => _resolveForRead().arrayBuffer();

  @override
  Future<String> text() => _resolveForRead().text();

  @override
  Stream<Uint8List> stream({int chunkSize = Block.defaultStreamChunkSize}) {
    return _resolveForRead().stream(chunkSize: chunkSize);
  }

  @override
  Uint8List _readRangeSync(int offset, int length) {
    final resolved = _resolved;
    if (resolved != null) {
      return resolved._readRangeSync(offset, length);
    }

    if (offset < 0 || length < 0 || offset + length > _length) {
      throw RangeError.range(offset + length, 0, _length, 'offset/length');
    }

    return _source._readRangeSync(_sourceOffset + offset, length);
  }

  _IoBlock _resolveForRead() {
    final existing = _resolved;
    if (existing != null) {
      return existing;
    }

    if (_length <= _sliceCopyThreshold) {
      final copied = _source._readRangeSync(_sourceOffset, _length);
      final backing = _IoBacking.fromBytes(copied);
      final resolved = _IoBlock._(backing, 0, _length, _type);
      _resolved = resolved;
      return resolved;
    }

    final sourceBlock = _materializeSourceBlock(_source);
    if (sourceBlock != null) {
      final resolved = _IoBlock._(
        sourceBlock._backing,
        sourceBlock._offset + _sourceOffset,
        _length,
        _type,
      );
      _resolved = resolved;
      return resolved;
    }

    final copied = _source._readRangeSync(_sourceOffset, _length);
    final backing = _IoBacking.fromBytes(copied);
    final resolved = _IoBlock._(backing, 0, _length, _type);
    _resolved = resolved;
    return resolved;
  }

  static _IoBlock? _materializeSourceBlock(_IoReadable source) {
    if (source is _IoBlock) {
      return source;
    }
    if (source is _IoComposedBlock) {
      return source._ensureMaterializedSync();
    }
    if (source is _IoDeferredSliceBlock) {
      return source._resolveForRead();
    }
    return null;
  }
}
