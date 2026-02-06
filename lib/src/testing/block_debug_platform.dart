import '../block.dart';
import 'block_debug_stub.dart'
    if (dart.library.io) 'block_debug_io.dart'
    if (dart.library.js_interop) 'block_debug_web.dart'
    as impl;

Map<String, Object?> debugBlock(Block block) => impl.debugBlock(block);

String ioBackingFilePrefix() => impl.ioBackingFilePrefix();
