import '../block.dart';
import 'io/io_block.dart';

Block createBlock(List<Object> parts, {String type = ''}) =>
    createIoBlock(parts, type: type);
