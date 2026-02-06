import '../block.dart';

Block createBlock(List<Object> parts, {String type = ''}) {
  throw UnsupportedError(
    'Block is only supported on dart:io and dart:js_interop platforms.',
  );
}
