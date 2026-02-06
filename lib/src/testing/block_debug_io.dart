import '../block.dart';
import '../platform/io/io_block.dart';

Map<String, Object?> debugBlock(Block block) => ioDebugMetadata(block);

String ioBackingFilePrefix() => ioTempFilePrefix;
