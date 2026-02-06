import 'dart:async';
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

  Future<void> _pending = Future<void>.value();

  static Future<_IoBacking> fromBytes(Uint8List bytes) {
    return fromChunks(Stream<Uint8List>.value(bytes), bytes.length);
  }

  static Future<_IoBacking> fromChunks(
    Stream<Uint8List> chunks,
    int totalSize,
  ) async {
    final path = _buildTempPath();
    final file = File(path);
    RandomAccessFile? handle;

    try {
      handle = await file.open(mode: FileMode.write);
      var written = 0;

      await for (final chunk in chunks) {
        if (chunk.isEmpty) {
          continue;
        }
        await handle.writeFrom(chunk);
        written += chunk.length;
      }

      if (written != totalSize) {
        throw StateError(
          'Unexpected write size for ${file.path}. Expected $totalSize, '
          'actual $written.',
        );
      }

      await handle.setPosition(0);
      return _IoBacking._(file, handle, totalSize);
    } catch (_) {
      if (handle != null) {
        try {
          await handle.close();
        } catch (_) {
          // best-effort cleanup.
        }
      }

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // best-effort cleanup.
      }

      rethrow;
    }
  }

  static String _buildTempPath() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final nonce = (_counter++).toRadixString(16);
    final separator = Platform.pathSeparator;
    return '${Directory.systemTemp.path}$separator$ioTempFilePrefix${now}_$nonce.tmp';
  }

  Future<Uint8List> readRange(int offset, int length) {
    _validateRange(totalSize, offset, length);
    if (length == 0) {
      return Future<Uint8List>.value(Uint8List(0));
    }

    return _enqueue(() async {
      await handle.setPosition(offset);
      final bytes = await handle.read(length);
      if (bytes.length != length) {
        throw StateError(
          'Unexpected end of file while reading $length bytes from '
          '${file.path}.',
        );
      }
      return bytes;
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    Future<void> runAction() async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }

    _pending = _pending.then<void>(
      (_) => runAction(),
      onError: (Object error, StackTrace stackTrace) => runAction(),
    );

    return completer.future;
  }
}

abstract interface class _IoReadable {
  int get size;

  Future<Uint8List> readRange(int offset, int length);

  Future<_IoBlock> ensureMaterialized();
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
    return _IoDeferredSliceBlock._fromSource(
      this,
      bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<Uint8List> arrayBuffer() => readRange(0, _length);

  @override
  Future<String> text() async => utf8.decode(await arrayBuffer());

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    _validateChunkSize(chunkSize);

    var readOffset = 0;
    while (readOffset < _length) {
      final toRead = min(chunkSize, _length - readOffset);
      yield await readRange(readOffset, toRead);
      readOffset += toRead;
    }
  }

  @override
  Future<Uint8List> readRange(int offset, int length) {
    _validateRange(_length, offset, length);
    return _backing.readRange(_offset + offset, length);
  }

  @override
  Future<_IoBlock> ensureMaterialized() => Future<_IoBlock>.value(this);
}

abstract base class _IoCompositePart {
  int get length;

  Future<Uint8List> readRange(int start, int length);

  Stream<Uint8List> stream();
}

final class _IoBytesPart extends _IoCompositePart {
  _IoBytesPart(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> readRange(int start, int length) async {
    _validateRange(_bytes.length, start, length);
    if (length == 0) {
      return Uint8List(0);
    }

    final end = start + length;
    return Uint8List.fromList(_bytes.sublist(start, end));
  }

  @override
  Stream<Uint8List> stream() async* {
    if (_bytes.isNotEmpty) {
      yield Uint8List.fromList(_bytes);
    }
  }
}

final class _IoReadablePart extends _IoCompositePart {
  _IoReadablePart(this._source, this._sourceOffset, this.length);

  final _IoReadable _source;
  final int _sourceOffset;

  @override
  final int length;

  @override
  Future<Uint8List> readRange(int start, int length) {
    _validateRange(this.length, start, length);
    return _source.readRange(_sourceOffset + start, length);
  }

  @override
  Stream<Uint8List> stream() {
    return _streamReadableRange(_source, _sourceOffset, length);
  }
}

final class _IoForeignBlockPart extends _IoCompositePart {
  _IoForeignBlockPart(this._block) : length = _block.size;

  final Block _block;

  @override
  final int length;

  @override
  Future<Uint8List> readRange(int start, int length) {
    _validateRange(this.length, start, length);
    if (length == 0) {
      return Future<Uint8List>.value(Uint8List(0));
    }

    return _block.slice(start, start + length).arrayBuffer();
  }

  @override
  Stream<Uint8List> stream() {
    if (length == 0) {
      return const Stream<Uint8List>.empty();
    }
    return _block.stream();
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
  Future<_IoBlock>? _materializing;

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
    return _IoDeferredSliceBlock._fromSource(
      this,
      bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<Uint8List> arrayBuffer() async {
    final materialized = await ensureMaterialized();
    return materialized.arrayBuffer();
  }

  @override
  Future<String> text() async {
    final materialized = await ensureMaterialized();
    return materialized.text();
  }

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    final materialized = await ensureMaterialized();
    yield* materialized.stream(chunkSize: chunkSize);
  }

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    final materialized = _materialized;
    if (materialized != null) {
      return materialized.readRange(offset, length);
    }
    return _readRangeFromParts(offset, length);
  }

  @override
  Future<_IoBlock> ensureMaterialized() {
    final existing = _materialized;
    if (existing != null) {
      return Future<_IoBlock>.value(existing);
    }

    final inFlight = _materializing;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _materialize();
    _materializing = future;
    return future;
  }

  Future<_IoBlock> _materialize() async {
    try {
      final backing = await _IoBacking.fromChunks(_streamAllParts(), _length);
      final materialized = _IoBlock._(backing, 0, _length, _type);
      _materialized = materialized;
      return materialized;
    } finally {
      _materializing = null;
    }
  }

  Stream<Uint8List> _streamAllParts() async* {
    for (final part in _parts) {
      yield* part.stream();
    }
  }

  Future<Uint8List> _readRangeFromParts(int offset, int length) async {
    _validateRange(_length, offset, length);
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
      final segment = await part.readRange(localStart, take);
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
      return _IoBytesPart(_utf8Bytes(part));
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
      return _IoForeignBlockPart(part);
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
  Future<_IoBlock>? _resolving;

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
  Future<Uint8List> arrayBuffer() async {
    final resolved = await _resolveForRead();
    return resolved.arrayBuffer();
  }

  @override
  Future<String> text() async {
    final resolved = await _resolveForRead();
    return resolved.text();
  }

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    final resolved = await _resolveForRead();
    yield* resolved.stream(chunkSize: chunkSize);
  }

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    final resolved = _resolved;
    if (resolved != null) {
      return resolved.readRange(offset, length);
    }

    _validateRange(_length, offset, length);
    return _source.readRange(_sourceOffset + offset, length);
  }

  @override
  Future<_IoBlock> ensureMaterialized() => _resolveForRead();

  Future<_IoBlock> _resolveForRead() {
    final existing = _resolved;
    if (existing != null) {
      return Future<_IoBlock>.value(existing);
    }

    final inFlight = _resolving;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _resolveInternal();
    _resolving = future;
    return future;
  }

  Future<_IoBlock> _resolveInternal() async {
    try {
      if (_length <= _sliceCopyThreshold) {
        final copied = await _source.readRange(_sourceOffset, _length);
        final backing = await _IoBacking.fromBytes(copied);
        final resolved = _IoBlock._(backing, 0, _length, _type);
        _resolved = resolved;
        return resolved;
      }

      final sourceBlock = await _source.ensureMaterialized();
      final resolved = _IoBlock._(
        sourceBlock._backing,
        sourceBlock._offset + _sourceOffset,
        _length,
        _type,
      );
      _resolved = resolved;
      return resolved;
    } finally {
      _resolving = null;
    }
  }
}

Stream<Uint8List> _streamReadableRange(
  _IoReadable source,
  int sourceOffset,
  int length,
) async* {
  var readOffset = 0;
  while (readOffset < length) {
    final toRead = min(Block.defaultStreamChunkSize, length - readOffset);
    yield await source.readRange(sourceOffset + readOffset, toRead);
    readOffset += toRead;
  }
}

Uint8List _utf8Bytes(String value) {
  return utf8.encode(value);
}

void _validateChunkSize(int chunkSize) {
  if (chunkSize <= 0) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be greater than 0');
  }
}

void _validateRange(int totalSize, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > totalSize) {
    throw RangeError.range(offset + length, 0, totalSize, 'offset/length');
  }
}
