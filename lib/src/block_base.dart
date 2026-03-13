import 'dart:convert';
import 'dart:typed_data';

import 'block.dart';

abstract base class BlockBase implements Block {
  @override
  Future<Uint8List> arrayBuffer() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream()) {
      if (chunk.isEmpty) {
        continue;
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<String> text() async => utf8.decode(await arrayBuffer());

  @override
  Stream<Uint8List> stream({int chunkSize = Block.defaultStreamChunkSize});
}
