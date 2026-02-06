import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../block.dart';
import '../slice_bounds.dart';

Block createWebBlock(List<Object> parts, {String type = ''}) {
  final normalized = _normalizeParts(parts);

  final directBlobParts = <JSAny>[];
  var allNative = true;
  for (final part in normalized.parts) {
    final nativePart = part.nativeBlobPart;
    if (nativePart == null) {
      allNative = false;
      break;
    }
    directBlobParts.add(nativePart);
  }

  if (allNative) {
    final blob = web.Blob(
      directBlobParts.toJS,
      web.BlobPropertyBag(type: type),
    );
    return _WebBlock._(blob);
  }

  return _WebComposedBlock._(normalized.parts, normalized.totalSize, type);
}

abstract interface class _WebBlobCarrier {
  int get size;

  Future<web.Blob> asBlob();
}

final class _WebBlock implements Block, _WebBlobCarrier {
  _WebBlock._(this._blob);

  final web.Blob _blob;

  @override
  int get size => _blob.size;

  @override
  String get type => _blob.type;

  @override
  Block slice(int start, [int? end, String? contentType]) {
    final bounds = normalizeSliceBounds(_blob.size, start, end);
    final next = _blob.slice(bounds.start, bounds.end, contentType ?? '');
    return _WebBlock._(next);
  }

  @override
  Future<Uint8List> arrayBuffer() => _blobToBytes(_blob);

  @override
  Future<String> text() => _blobToText(_blob);

  @override
  Stream<Uint8List> stream({int chunkSize = Block.defaultStreamChunkSize}) =>
      _blobToStream(_blob, chunkSize: chunkSize);

  @override
  Future<web.Blob> asBlob() => Future<web.Blob>.value(_blob);
}

final class _WebComposedBlock implements Block, _WebBlobCarrier {
  _WebComposedBlock._(this._parts, this._length, this._type);

  final List<_WebCompositePart> _parts;
  final int _length;
  final String _type;

  _WebBlock? _materialized;
  Future<_WebBlock>? _materializing;

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
    return _WebDeferredSliceBlock._fromSource(
      this,
      bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<Uint8List> arrayBuffer() async {
    final blob = await asBlob();
    return _blobToBytes(blob);
  }

  @override
  Future<String> text() async {
    final blob = await asBlob();
    return _blobToText(blob);
  }

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    final blob = await asBlob();
    yield* _blobToStream(blob, chunkSize: chunkSize);
  }

  @override
  Future<web.Blob> asBlob() async {
    final existing = _materialized;
    if (existing != null) {
      return existing._blob;
    }

    final inFlight = _materializing;
    if (inFlight != null) {
      return (await inFlight)._blob;
    }

    final future = _materialize();
    _materializing = future;
    final materialized = await future;
    return materialized._blob;
  }

  Future<_WebBlock> _materialize() async {
    try {
      final blobParts = <JSAny>[];
      for (final part in _parts) {
        blobParts.add(await part.toBlobPart());
      }

      final blob = web.Blob(blobParts.toJS, web.BlobPropertyBag(type: _type));
      final materialized = _WebBlock._(blob);
      _materialized = materialized;
      return materialized;
    } finally {
      _materializing = null;
    }
  }
}

final class _WebDeferredSliceBlock implements Block, _WebBlobCarrier {
  _WebDeferredSliceBlock._(
    this._source,
    this._sourceOffset,
    this._length,
    this._type,
  );

  factory _WebDeferredSliceBlock._fromSource(
    _WebBlobCarrier source,
    int sourceOffset,
    int length,
    String type,
  ) {
    var normalizedSource = source;
    var normalizedOffset = sourceOffset;

    while (normalizedSource is _WebDeferredSliceBlock) {
      normalizedOffset += normalizedSource._sourceOffset;
      normalizedSource = normalizedSource._source;
    }

    return _WebDeferredSliceBlock._(
      normalizedSource,
      normalizedOffset,
      length,
      type,
    );
  }

  final _WebBlobCarrier _source;
  final int _sourceOffset;
  final int _length;
  final String _type;

  _WebBlock? _materialized;
  Future<_WebBlock>? _materializing;

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
    return _WebDeferredSliceBlock._fromSource(
      _source,
      _sourceOffset + bounds.start,
      bounds.length,
      contentType ?? '',
    );
  }

  @override
  Future<Uint8List> arrayBuffer() async {
    final blob = await asBlob();
    return _blobToBytes(blob);
  }

  @override
  Future<String> text() async {
    final blob = await asBlob();
    return _blobToText(blob);
  }

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    final blob = await asBlob();
    yield* _blobToStream(blob, chunkSize: chunkSize);
  }

  @override
  Future<web.Blob> asBlob() async {
    final existing = _materialized;
    if (existing != null) {
      return existing._blob;
    }

    final inFlight = _materializing;
    if (inFlight != null) {
      return (await inFlight)._blob;
    }

    final future = _materialize();
    _materializing = future;
    final materialized = await future;
    return materialized._blob;
  }

  Future<_WebBlock> _materialize() async {
    try {
      final sourceBlob = await _source.asBlob();
      final sliced = sourceBlob.slice(
        _sourceOffset,
        _sourceOffset + _length,
        _type,
      );
      final materialized = _WebBlock._(sliced);
      _materialized = materialized;
      return materialized;
    } finally {
      _materializing = null;
    }
  }
}

abstract base class _WebCompositePart {
  int get size;

  JSAny? get nativeBlobPart;

  Future<JSAny> toBlobPart();
}

final class _WebBytesPart extends _WebCompositePart {
  _WebBytesPart(this._bytes);

  final Uint8List _bytes;

  @override
  int get size => _bytes.length;

  @override
  JSAny? get nativeBlobPart => _bytes.toJS;

  @override
  Future<JSAny> toBlobPart() async => _bytes.toJS;
}

final class _WebBlobPart extends _WebCompositePart {
  _WebBlobPart(this._blob);

  final web.Blob _blob;

  @override
  int get size => _blob.size;

  @override
  JSAny? get nativeBlobPart => _blob;

  @override
  Future<JSAny> toBlobPart() async => _blob;
}

final class _WebBlobCarrierPart extends _WebCompositePart {
  _WebBlobCarrierPart(this._carrier);

  final _WebBlobCarrier _carrier;

  @override
  int get size => _carrier.size;

  @override
  JSAny? get nativeBlobPart => null;

  @override
  Future<JSAny> toBlobPart() async => await _carrier.asBlob();
}

final class _WebForeignBlockPart extends _WebCompositePart {
  _WebForeignBlockPart(this._block) : _length = _block.size;

  final Block _block;
  final int _length;

  @override
  int get size => _length;

  @override
  JSAny? get nativeBlobPart => null;

  @override
  Future<JSAny> toBlobPart() async {
    final bytes = await _block.arrayBuffer();
    return bytes.toJS;
  }
}

({List<_WebCompositePart> parts, int totalSize}) _normalizeParts(
  List<Object> parts,
) {
  if (parts.isEmpty) {
    return (parts: const <_WebCompositePart>[], totalSize: 0);
  }

  final normalized = <_WebCompositePart>[];
  var totalSize = 0;

  for (final part in parts) {
    final normalizedPart = _normalizePart(part);
    if (normalizedPart.size == 0) {
      continue;
    }

    normalized.add(normalizedPart);
    totalSize += normalizedPart.size;
  }

  return (
    parts: List<_WebCompositePart>.unmodifiable(normalized),
    totalSize: totalSize,
  );
}

_WebCompositePart _normalizePart(Object part) {
  if (part is String) {
    return _WebBytesPart(_utf8Bytes(part));
  }

  if (part is Uint8List) {
    return _WebBytesPart(Uint8List.fromList(part));
  }

  if (part is ByteData) {
    return _WebBytesPart(
      Uint8List.fromList(
        part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes),
      ),
    );
  }

  // ignore: invalid_runtime_check_with_js_interop_types
  if (part is web.Blob) {
    return _WebBlobPart(part);
  }

  if (part is _WebBlock) {
    return _WebBlobPart(part._blob);
  }

  if (part is _WebBlobCarrier) {
    return _WebBlobCarrierPart(part);
  }

  if (part is Block) {
    return _WebForeignBlockPart(part);
  }

  throw ArgumentError(
    'Unsupported part type: ${part.runtimeType}. '
    'Supported types are String, Uint8List, ByteData, Block, and web.Blob/web.File.',
  );
}

Future<Uint8List> _blobToBytes(web.Blob blob) async {
  final jsBuffer = await blob.arrayBuffer().toDart;
  final jsBytes = JSUint8Array(jsBuffer);
  return Uint8List.fromList(jsBytes.toDart);
}

Future<String> _blobToText(web.Blob blob) async {
  final jsText = await blob.text().toDart;
  return jsText.toDart;
}

Stream<Uint8List> _blobToStream(
  web.Blob blob, {
  required int chunkSize,
}) async* {
  if (chunkSize <= 0) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be greater than 0');
  }

  final reader = blob.stream().getReader() as web.ReadableStreamDefaultReader;

  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) {
        break;
      }

      final data = (result.value! as JSUint8Array).toDart;
      if (data.length <= chunkSize) {
        yield Uint8List.fromList(data);
        continue;
      }

      var offset = 0;
      while (offset < data.length) {
        final nextOffset = min(offset + chunkSize, data.length);
        yield Uint8List.fromList(data.sublist(offset, nextOffset));
        offset = nextOffset;
      }
    }
  } finally {
    try {
      await reader.cancel().toDart;
    } catch (_) {
      // Reader can already be closed; ignore cleanup failure.
    }
  }
}

Uint8List _utf8Bytes(String value) {
  return utf8.encode(value);
}
