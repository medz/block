import 'dart:typed_data';

import 'package:block/block.dart';
import 'package:block/src/testing/block_debug.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('io backend uses temp file and slice threshold strategy', (
    tester,
  ) async {
    final source = Uint8List.fromList(
      List<int>.generate(300 * 1024, (i) => i % 256),
    );

    final block = Block(<Object>[source], type: 'application/octet-stream');
    expect(blockImplementation(block), equals('io'));

    final smallSlice = block.slice(0, 1024);
    final largeSlice = block.slice(0, 128 * 1024);

    final parentBacking = ioBackingIdentity(block);
    expect(parentBacking, isNotNull);

    expect(ioBackingIdentity(smallSlice), isNot(equals(parentBacking)));
    expect(ioBackingIdentity(largeSlice), equals(parentBacking));

    final path = ioBackingPath(block);
    expect(path, isNotNull);
    expect(path!.contains(ioBackingFilePrefix()), isTrue);
  });
}
