import '../block.dart';
import 'block_factory_stub.dart'
    if (dart.library.io) 'block_factory_io.dart'
    if (dart.library.js_interop) 'block_factory_web.dart'
    as impl;

Block createBlock(List<Object> parts, {String type = ''}) =>
    impl.createBlock(parts, type: type);
