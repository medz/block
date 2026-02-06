import '../block.dart';
import 'block_debug_platform.dart' as platform;

Map<String, Object?> debugBlock(Block block) => platform.debugBlock(block);

String blockImplementation(Block block) {
  final implementation = debugBlock(block)['implementation'];
  if (implementation is String) {
    return implementation;
  }
  return 'unknown';
}

String? ioBackingPath(Block block) =>
    debugBlock(block)['backingPath'] as String?;

int? ioBackingIdentity(Block block) =>
    debugBlock(block)['backingIdentity'] as int?;

String ioBackingFilePrefix() => platform.ioBackingFilePrefix();
