import 'dart:convert';
import 'dart:typed_data';

import 'block.dart';
import 'utils.dart';

abstract base class BlockBase implements Block {
  @override
  Future<String> text() async => utf8.decode(await arrayBuffer());

  @override
  Stream<Uint8List> stream({
    int chunkSize = Block.defaultStreamChunkSize,
  }) async* {
    validateChunkSize(chunkSize);
    final bytes = await arrayBuffer();
    yield* chunkedBytes(bytes, chunkSize: chunkSize);
  }
}
