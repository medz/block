import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'block.dart';
import 'block_base.dart';
import 'block_memory.dart';
import 'utils.dart' show normalizeSliceBounds, validateChunkSize;

typedef _WebPart = ({
  int size,
  JSAny? nativeBlobPart,
  Future<JSAny> Function() toBlobPart,
});

Block createBlock(List<Object> parts, {String type = ''}) {
  final normalized = _normalizeParts(parts);

  final directParts = <JSAny>[];
  var allNative = true;
  for (final part in normalized.parts) {
    final native = part.nativeBlobPart;
    if (native == null) {
      allNative = false;
      break;
    }
    directParts.add(native);
  }

  if (allNative) {
    final blob = web.Blob(directParts.toJS, web.BlobPropertyBag(type: type));
    return _WebNativeBlock._(blob);
  }

  return _WebLazyBlock._fromParts(normalized.parts, normalized.totalSize, type);
}

abstract interface class _WebBlobSource {
  int get size;

  Future<web.Blob> asBlob();
}

abstract base class _WebBlobBlock extends BlockBase
    implements Block, _WebBlobSource {
  @override
  Future<Uint8List> arrayBuffer() async => _blobToBytes(await asBlob());

  @override
  Future<String> text() async => _blobToText(await asBlob());

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    final blob = await asBlob();
    yield* _blobToStream(blob, chunkSize: chunkSize);
  }
}

final class _WebNativeBlock extends _WebBlobBlock {
  _WebNativeBlock._(this._blob);

  final web.Blob _blob;

  @override
  int get size => _blob.size;

  @override
  String get type => _blob.type;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final bounds = normalizeSliceBounds(_blob.size, start, end);
    final next = _blob.slice(bounds.start, bounds.end, contentType ?? '');
    return _WebNativeBlock._(next);
  }

  @override
  Future<web.Blob> asBlob() async => _blob;
}

final class _WebLazyBlock extends _WebBlobBlock {
  _WebLazyBlock._fromParts(this._parts, this._length, this._type)
    : _source = null,
      _sourceOffset = 0;

  _WebLazyBlock._fromSourceRaw(
    this._source,
    this._sourceOffset,
    this._length,
    this._type,
  ) : _parts = null;

  factory _WebLazyBlock._fromSource(
    _WebBlobSource source,
    int sourceOffset,
    int length,
    String type,
  ) {
    var normalizedSource = source;
    var normalizedOffset = sourceOffset;

    while (normalizedSource is _WebLazyBlock &&
        normalizedSource._source != null) {
      normalizedOffset += normalizedSource._sourceOffset;
      normalizedSource = normalizedSource._source;
    }

    return _WebLazyBlock._fromSourceRaw(
      normalizedSource,
      normalizedOffset,
      length,
      type,
    );
  }

  final List<_WebPart>? _parts;
  final _WebBlobSource? _source;
  final int _sourceOffset;
  final int _length;
  final String _type;

  _WebNativeBlock? _materialized;
  Future<_WebNativeBlock>? _materializing;

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
    return _WebLazyBlock._fromSource(
      this,
      bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<web.Blob> asBlob() async {
    final materialized = _materialized;
    if (materialized != null) {
      return materialized._blob;
    }

    final inFlight = _materializing;
    if (inFlight != null) {
      return (await inFlight)._blob;
    }

    final future = _materialize();
    _materializing = future;
    final resolved = await future;
    return resolved._blob;
  }

  Future<_WebNativeBlock> _materialize() async {
    try {
      if (_isComposed) {
        final blobParts = <JSAny>[];
        for (final part in _parts!) {
          blobParts.add(await part.toBlobPart());
        }
        final blob = web.Blob(blobParts.toJS, web.BlobPropertyBag(type: _type));
        final block = _WebNativeBlock._(blob);
        _materialized = block;
        return block;
      }

      final sourceBlob = await _source!.asBlob();
      final sliced = sourceBlob.slice(
        _sourceOffset,
        _sourceOffset + _length,
        _type,
      );
      final block = _WebNativeBlock._(sliced);
      _materialized = block;
      return block;
    } finally {
      _materializing = null;
    }
  }
}

({List<_WebPart> parts, int totalSize}) _normalizeParts(List<Object> parts) {
  if (parts.isEmpty) {
    return (parts: const <_WebPart>[], totalSize: 0);
  }

  final normalized = <_WebPart>[];
  var totalSize = 0;

  for (final part in parts) {
    final normalizedPart = _normalizePart(part);
    if (normalizedPart.size == 0) {
      continue;
    }

    normalized.add(normalizedPart);
    totalSize += normalizedPart.size;
  }

  return (parts: List<_WebPart>.unmodifiable(normalized), totalSize: totalSize);
}

_WebPart _normalizePart(Object part) {
  if (part is String) {
    final bytes = utf8.encode(part);
    return (
      size: bytes.length,
      nativeBlobPart: bytes.toJS,
      toBlobPart: () async => bytes.toJS,
    );
  }

  if (part is Uint8List) {
    final bytes = part;
    return (
      size: bytes.length,
      nativeBlobPart: bytes.toJS,
      toBlobPart: () async => bytes.toJS,
    );
  }

  if (part is ByteData) {
    final bytes = part.buffer.asUint8List(
      part.offsetInBytes,
      part.lengthInBytes,
    );
    return (
      size: bytes.length,
      nativeBlobPart: bytes.toJS,
      toBlobPart: () async => bytes.toJS,
    );
  }

  if (part is MemoryBlock) {
    final bytes = part.copyBytesSync();
    return (
      size: bytes.length,
      nativeBlobPart: bytes.toJS,
      toBlobPart: () async => bytes.toJS,
    );
  }

  // ignore: invalid_runtime_check_with_js_interop_types
  if (part is web.Blob) {
    return (
      size: part.size,
      nativeBlobPart: part,
      toBlobPart: () async => part,
    );
  }

  if (part is _WebNativeBlock) {
    final blob = part._blob;
    return (
      size: blob.size,
      nativeBlobPart: blob,
      toBlobPart: () async => blob,
    );
  }

  if (part is _WebBlobSource) {
    return (
      size: part.size,
      nativeBlobPart: null,
      toBlobPart: () async => await part.asBlob(),
    );
  }

  if (part is Block) {
    return (
      size: part.size,
      nativeBlobPart: null,
      toBlobPart: () async {
        final bytes = await part.arrayBuffer();
        return bytes.toJS;
      },
    );
  }

  throw ArgumentError(
    'Unsupported part type: ${part.runtimeType}. '
    'Supported types are String, Uint8List, ByteData, Block, and '
    'web.Blob/web.File.',
  );
}

Future<Uint8List> _blobToBytes(web.Blob blob) async {
  final jsBuffer = await blob.arrayBuffer().toDart;
  final jsBytes = JSUint8Array(jsBuffer);
  return jsBytes.toDart;
}

Future<String> _blobToText(web.Blob blob) async {
  final jsText = await blob.text().toDart;
  return jsText.toDart;
}

Stream<Uint8List> _blobToStream(
  web.Blob blob, {
  required int chunkSize,
}) async* {
  validateChunkSize(chunkSize);

  final reader = blob.stream().getReader() as web.ReadableStreamDefaultReader;

  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) {
        break;
      }

      final data = (result.value! as JSUint8Array).toDart;
      if (data.length <= chunkSize) {
        yield data;
        continue;
      }

      var offset = 0;
      while (offset < data.length) {
        final nextOffset = min(offset + chunkSize, data.length);
        yield Uint8List.sublistView(data, offset, nextOffset);
        offset = nextOffset;
      }
    }
  } finally {
    try {
      await reader.cancel().toDart;
    } catch (_) {
      // Reader may already be closed.
    }
  }
}
