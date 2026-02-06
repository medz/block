import '../block.dart';
import '../platform/web/web_block.dart';

Map<String, Object?> debugBlock(Block block) => webDebugMetadata(block);

String ioBackingFilePrefix() => 'block_io_';
