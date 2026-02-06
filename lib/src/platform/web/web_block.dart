import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../block.dart';
import '../slice_bounds.dart';

Block createWebBlock(List<Object> parts, {String type = ''}) =>
    _WebBlock._fromParts(parts, type: type);

Map<String, Object?> webDebugMetadata(Block block) {
  if (block is! _WebBlock) {
    return const {'implementation': 'unknown'};
  }

  return {
    'implementation': 'web',
    'size': block._blob.size,
    'type': block._blob.type,
  };
}

final class _WebBlock implements Block {
  _WebBlock._(this._blob);

  factory _WebBlock._fromParts(List<Object> parts, {String type = ''}) {
    final blobParts = <JSAny>[];
    for (final part in parts) {
      blobParts.add(_toBlobPart(part));
    }

    final blob = web.Blob(blobParts.toJS, web.BlobPropertyBag(type: type));
    return _WebBlock._(blob);
  }

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
  Future<Uint8List> arrayBuffer() async {
    final jsBuffer = await _blob.arrayBuffer().toDart;
    final jsBytes = JSUint8Array(jsBuffer);
    return Uint8List.fromList(jsBytes.toDart);
  }

  @override
  Future<String> text() async {
    final jsText = await _blob.text().toDart;
    return jsText.toDart;
  }

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

    final reader =
        _blob.stream().getReader() as web.ReadableStreamDefaultReader;

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

  static JSAny _toBlobPart(Object part) {
    if (part is String) {
      return part.toJS;
    }

    if (part is Uint8List) {
      return Uint8List.fromList(part).toJS;
    }

    if (part is ByteData) {
      final bytes = Uint8List.fromList(
        part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes),
      );
      return bytes.toJS;
    }

    if (part is Block) {
      if (part is _WebBlock) {
        return part._blob;
      }
      throw ArgumentError(
        'Unsupported Block implementation ${part.runtimeType} on web platform. '
        'Use Block instances created by this package on the same platform.',
      );
    }

    throw ArgumentError(
      'Unsupported part type: ${part.runtimeType}. '
      'Supported types are String, Uint8List, ByteData, and Block.',
    );
  }
}
