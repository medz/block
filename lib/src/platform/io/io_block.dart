import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../block.dart';
import '../slice_bounds.dart';

const String ioTempFilePrefix = 'block_io_';
const int _sliceCopyThreshold = 64 * 1024;

Block createIoBlock(List<Object> parts, {String type = ''}) =>
    _IoBlock._fromParts(parts, type: type);

Map<String, Object?> ioDebugMetadata(Block block) {
  if (block is! _IoBlock) {
    return const {
      'implementation': 'unknown',
      'backingPath': null,
      'backingIdentity': null,
      'offset': null,
      'length': null,
    };
  }

  return {
    'implementation': 'io',
    'backingPath': block._backing.file.path,
    'backingIdentity': identityHashCode(block._backing),
    'offset': block._offset,
    'length': block._length,
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

  static final Random _random = Random();

  final File file;
  final RandomAccessFile handle;
  final int totalSize;

  static _IoBacking fromBytes(Uint8List bytes) {
    final path = _buildTempPath();
    final file = File(path);
    file.writeAsBytesSync(bytes, flush: true);
    final handle = file.openSync(mode: FileMode.read);
    return _IoBacking._(file, handle, bytes.length);
  }

  static String _buildTempPath() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final nonce = _random.nextInt(1 << 32).toRadixString(16);
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

    return Uint8List.fromList(bytes);
  }
}

final class _IoBlock implements Block {
  _IoBlock._(this._backing, this._offset, this._length, this._type);

  factory _IoBlock._fromParts(List<Object> parts, {String type = ''}) {
    final bytes = _flattenParts(parts);
    final backing = _IoBacking.fromBytes(bytes);
    return _IoBlock._(backing, 0, bytes.length, type);
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
      yield _backing.readRangeSync(_offset + readOffset, toRead);
      readOffset += toRead;
    }
  }

  Uint8List _readViewSync() => _backing.readRangeSync(_offset, _length);

  static Uint8List _flattenParts(List<Object> parts) {
    if (parts.isEmpty) {
      return Uint8List(0);
    }

    final chunks = <Uint8List>[];
    var totalSize = 0;

    for (final part in parts) {
      final bytes = _partToBytes(part);
      chunks.add(bytes);
      totalSize += bytes.length;
    }

    final merged = Uint8List(totalSize);
    var cursor = 0;
    for (final chunk in chunks) {
      merged.setRange(cursor, cursor + chunk.length, chunk);
      cursor += chunk.length;
    }

    return merged;
  }

  static Uint8List _partToBytes(Object part) {
    if (part is String) {
      return Uint8List.fromList(utf8.encode(part));
    }

    if (part is Uint8List) {
      return Uint8List.fromList(part);
    }

    if (part is ByteData) {
      return Uint8List.fromList(
        part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes),
      );
    }

    if (part is _IoBlock) {
      return part._readViewSync();
    }

    if (part is Block) {
      throw ArgumentError(
        'Unsupported Block implementation ${part.runtimeType} on io platform.',
      );
    }

    throw ArgumentError(
      'Unsupported part type: ${part.runtimeType}. '
      'Supported types are String, Uint8List, ByteData, and Block.',
    );
  }
}
