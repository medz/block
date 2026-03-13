import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'block.dart';
import 'block_base.dart';
import 'block_memory.dart';
import 'utils.dart' show normalizeSliceBounds, validateChunkSize;

const String ioTempFilePrefix = 'block_io_';
const int _sliceCopyThreshold = 64 * 1024;
const int _smallInMemoryThreshold = 64 * 1024;
const int _materializeChunkSize = 1024 * 1024;

typedef _BlockPart = ({Block block, int length});

Block createBlock(List<Object> parts, {String type = ''}) {
  final memory = MemoryBlock.tryFromParts(
    parts,
    type: type,
    threshold: _smallInMemoryThreshold,
  );
  if (memory != null) {
    return memory;
  }

  final normalized = _normalizeParts(parts);
  return _IoLazyBlock._fromParts(normalized.parts, normalized.totalSize, type);
}

final class _IoBacking {
  _IoBacking._(
    this.file,
    this._handle,
    this.totalSize, {
    required this.deleteOnCleanup,
  }) {
    _ioHandleFinalizer.attach(
      this,
      _IoCleanupToken(file.path, _handle, deleteOnCleanup),
      detach: this,
    );
  }

  static int _counter = 0;

  final File file;
  final RandomAccessFile _handle;
  final int totalSize;
  final bool deleteOnCleanup;
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
    RandomAccessFile? writer;
    RandomAccessFile? reader;

    try {
      writer = await file.open(mode: FileMode.write);
      var written = 0;

      await for (final chunk in chunks) {
        if (chunk.isEmpty) {
          continue;
        }
        await writer.writeFrom(chunk);
        written += chunk.length;
      }

      if (written != totalSize) {
        throw StateError(
          'Unexpected write size for ${file.path}. Expected $totalSize, '
          'actual $written.',
        );
      }

      await writer.close();
      writer = null;

      reader = await file.open(mode: FileMode.read);
      return _IoBacking._(file, reader, totalSize, deleteOnCleanup: true);
    } catch (_) {
      if (writer != null) {
        try {
          await writer.close();
        } catch (_) {
          // Best-effort cleanup.
        }
      }

      if (reader != null) {
        try {
          await reader.close();
        } catch (_) {
          // Best-effort cleanup.
        }
      }

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup.
      }

      rethrow;
    }
  }

  static Future<_IoBacking> fromFileWithSize(File file, int totalSize) async {
    final reader = await file.open(mode: FileMode.read);
    return _IoBacking._(file, reader, totalSize, deleteOnCleanup: false);
  }

  static String _buildTempPath() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final nonce = (_counter++).toRadixString(16);
    final separator = Platform.pathSeparator;
    return '${Directory.systemTemp.path}$separator$ioTempFilePrefix${now}_$nonce.tmp';
  }

  Future<Uint8List> readRange(int offset, int length) async {
    _validateRange(totalSize, offset, length);
    if (length == 0) {
      return Uint8List(0);
    }

    return _enqueue(() async {
      await _handle.setPosition(offset);
      final bytes = await _handle.read(length);
      if (bytes.length != length) {
        throw StateError(
          'Unexpected end of file while reading $length bytes from '
          '${file.path}.',
        );
      }
      return bytes;
    });
  }

  Stream<Uint8List> streamRange(
    int offset,
    int length, {
    required int chunkSize,
  }) async* {
    validateChunkSize(chunkSize);
    _validateRange(totalSize, offset, length);
    if (length == 0) {
      return;
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(offset);
      var remaining = length;
      while (remaining > 0) {
        final toRead = min(chunkSize, remaining);
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) {
          throw StateError(
            'Unexpected end of file while streaming ${file.path}.',
          );
        }
        yield chunk;
        remaining -= chunk.length;
      }
    } finally {
      try {
        await raf.close();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
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
      onError: (Object _, StackTrace _) => runAction(),
    );

    return completer.future;
  }
}

final class _IoCleanupToken {
  _IoCleanupToken(this.path, this.handle, this.deleteOnCleanup);

  final String path;
  final RandomAccessFile handle;
  final bool deleteOnCleanup;
}

final Finalizer<_IoCleanupToken> _ioHandleFinalizer =
    Finalizer<_IoCleanupToken>((token) {
      try {
        token.handle.closeSync();
      } catch (_) {
        // Best-effort cleanup.
      }

      if (!token.deleteOnCleanup) {
        return;
      }

      try {
        final file = File(token.path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // Best-effort cleanup.
      }
    });

abstract interface class _IoReadable {
  int get size;

  Future<Uint8List> readRange(int offset, int length);

  Future<FileBlock> ensureMaterialized();
}

/// A [Block] view backed by a `dart:io` [File].
///
/// The file length is captured when the block is opened. Callers must treat the
/// source file as immutable for the lifetime of the block.
final class FileBlock extends BlockBase implements _IoReadable {
  FileBlock._(this._backing, this._offset, this._length, this._type);

  /// Opens an entire [file] as a lazy, file-backed [Block].
  static Future<FileBlock> open(File file, {String type = ''}) async {
    final totalSize = await file.length();
    return _openWithKnownSize(
      file,
      totalSize: totalSize,
      offset: 0,
      length: totalSize,
      type: type,
    );
  }

  /// Opens a byte range of [file] as a lazy, file-backed [Block].
  static Future<FileBlock> openRange(
    File file, {
    required int offset,
    required int length,
    String type = '',
  }) async {
    final totalSize = await file.length();
    _validateRange(totalSize, offset, length);
    return _openWithKnownSize(
      file,
      totalSize: totalSize,
      offset: offset,
      length: length,
      type: type,
    );
  }

  static Future<FileBlock> _openWithKnownSize(
    File file, {
    required int totalSize,
    required int offset,
    required int length,
    required String type,
  }) async {
    final backing = await _IoBacking.fromFileWithSize(file, totalSize);
    return FileBlock._(backing, offset, length, type);
  }

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
    return FileBlock._(
      _backing,
      _offset + bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<Uint8List> arrayBuffer() => _backing.readRange(_offset, _length);

  @override
  Stream<Uint8List> stream({int chunkSize = Block.defaultStreamChunkSize}) {
    return _backing.streamRange(_offset, _length, chunkSize: chunkSize);
  }

  @override
  Future<Uint8List> readRange(int offset, int length) {
    _validateRange(_length, offset, length);
    return _backing.readRange(_offset + offset, length);
  }

  @override
  Future<FileBlock> ensureMaterialized() async => this;
}

final class _IoFileRefBlock extends BlockBase implements _IoReadable {
  _IoFileRefBlock(
    this._file,
    this._fileSize,
    this._offset,
    this._length,
    this._type,
  );

  final File _file;
  final int _fileSize;
  final int _offset;
  final int _length;
  final String _type;

  WeakReference<FileBlock>? _opened;
  Future<FileBlock>? _opening;

  @override
  int get size => _length;

  @override
  String get type => _type;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final bounds = normalizeSliceBounds(_length, start, end);
    return _IoFileRefBlock(
      _file,
      _fileSize,
      _offset + bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<Uint8List> arrayBuffer() async {
    final opened = await ensureMaterialized();
    return opened.arrayBuffer();
  }

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    final opened = await ensureMaterialized();
    yield* opened.stream(chunkSize: chunkSize);
  }

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    final opened = await ensureMaterialized();
    return opened.readRange(offset, length);
  }

  @override
  Future<FileBlock> ensureMaterialized() {
    final cached = _opened?.target;
    if (cached != null) {
      return Future<FileBlock>.value(cached);
    }

    final inFlight = _opening;
    if (inFlight != null) {
      return inFlight;
    }

    final future = FileBlock._openWithKnownSize(
      _file,
      totalSize: _fileSize,
      offset: _offset,
      length: _length,
      type: _type,
    );

    _opening = future;
    return future
        .then((block) {
          _opened = WeakReference<FileBlock>(block);
          return block;
        })
        .whenComplete(() {
          _opening = null;
        });
  }
}

final class _IoLazyBlock extends BlockBase implements _IoReadable {
  _IoLazyBlock._fromParts(this._parts, this._length, this._type)
    : _source = null,
      _sourceOffset = 0;

  _IoLazyBlock._fromSourceRaw(
    this._source,
    this._sourceOffset,
    this._length,
    this._type,
  ) : _parts = null;

  factory _IoLazyBlock._fromSource(
    _IoReadable source,
    int sourceOffset,
    int length,
    String type,
  ) {
    var normalizedSource = source;
    var normalizedOffset = sourceOffset;

    while (normalizedSource is _IoLazyBlock &&
        normalizedSource._source != null) {
      normalizedOffset += normalizedSource._sourceOffset;
      normalizedSource = normalizedSource._source;
    }

    return _IoLazyBlock._fromSourceRaw(
      normalizedSource,
      normalizedOffset,
      length,
      type,
    );
  }

  final List<_BlockPart>? _parts;
  final _IoReadable? _source;
  final int _sourceOffset;
  final int _length;
  final String _type;

  FileBlock? _materialized;
  Future<FileBlock>? _materializing;

  bool get _isComposed => _parts != null;

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
    return _IoLazyBlock._fromSource(
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
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    if (_isComposed) {
      validateChunkSize(chunkSize);
      for (final part in _parts!) {
        yield* part.block.stream(chunkSize: chunkSize);
      }
      return;
    }

    final materialized = await ensureMaterialized();
    yield* materialized.stream(chunkSize: chunkSize);
  }

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    final materialized = _materialized;
    if (materialized != null) {
      return materialized.readRange(offset, length);
    }

    if (_isComposed) {
      return _readRangeFromParts(offset, length);
    }

    _validateRange(_length, offset, length);
    return _source!.readRange(_sourceOffset + offset, length);
  }

  @override
  Future<FileBlock> ensureMaterialized() {
    final existing = _materialized;
    if (existing != null) {
      return Future<FileBlock>.value(existing);
    }

    final inFlight = _materializing;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _materialize();
    _materializing = future;
    return future;
  }

  Future<FileBlock> _materialize() async {
    try {
      if (_isComposed) {
        final backing = await _IoBacking.fromChunks(
          stream(chunkSize: _materializeChunkSize),
          _length,
        );
        final block = FileBlock._(backing, 0, _length, _type);
        _materialized = block;
        return block;
      }

      if (_length <= _sliceCopyThreshold) {
        final copied = await _source!.readRange(_sourceOffset, _length);
        final backing = await _IoBacking.fromBytes(copied);
        final block = FileBlock._(backing, 0, _length, _type);
        _materialized = block;
        return block;
      }

      final sourceBlock = await _source!.ensureMaterialized();
      final block = FileBlock._(
        sourceBlock._backing,
        sourceBlock._offset + _sourceOffset,
        _length,
        _type,
      );
      _materialized = block;
      return block;
    } finally {
      _materializing = null;
    }
  }

  Future<Uint8List> _readRangeFromParts(int offset, int length) async {
    _validateRange(_length, offset, length);
    if (length == 0) {
      return Uint8List(0);
    }

    final output = Uint8List(length);
    var outputOffset = 0;
    var remainingSkip = offset;
    var remainingLength = length;

    for (final part in _parts!) {
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
      final segment = await _readBlockRange(part.block, localStart, take);
      output.setRange(outputOffset, outputOffset + take, segment);

      outputOffset += take;
      remainingLength -= take;
      remainingSkip = 0;
    }

    return output;
  }
}

({List<_BlockPart> parts, int totalSize}) _normalizeParts(List<Object> parts) {
  if (parts.isEmpty) {
    return (parts: const <_BlockPart>[], totalSize: 0);
  }

  final normalized = <_BlockPart>[];
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
    parts: List<_BlockPart>.unmodifiable(normalized),
    totalSize: totalSize,
  );
}

_BlockPart _normalizePart(Object part) {
  if (part is String) {
    final block = MemoryBlock.fromBytes(utf8.encode(part));
    return (block: block, length: block.size);
  }

  if (part is Uint8List) {
    final block = MemoryBlock.fromBytes(part);
    return (block: block, length: block.size);
  }

  if (part is ByteData) {
    final block = MemoryBlock.fromBytes(
      part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes),
    );
    return (block: block, length: block.size);
  }

  if (part is MemoryBlock) {
    return (block: part, length: part.size);
  }

  if (part is File) {
    final fileSize = part.lengthSync();
    return (
      block: _IoFileRefBlock(part, fileSize, 0, fileSize, ''),
      length: fileSize,
    );
  }

  if (part is _IoReadable && part is Block) {
    return (block: part as Block, length: part.size);
  }

  if (part is Block) {
    return (block: part, length: part.size);
  }

  throw ArgumentError(
    'Unsupported part type: ${part.runtimeType}. '
    'Supported types are String, Uint8List, ByteData, File, and Block.',
  );
}

Future<Uint8List> _readBlockRange(Block block, int offset, int length) {
  if (length == 0) {
    return Future<Uint8List>.value(Uint8List(0));
  }

  if (block is _IoReadable) {
    return (block as _IoReadable).readRange(offset, length);
  }

  return block.slice(offset, offset + length).arrayBuffer();
}

void _validateRange(int totalSize, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > totalSize) {
    throw RangeError.range(offset + length, 0, totalSize, 'offset/length');
  }
}
