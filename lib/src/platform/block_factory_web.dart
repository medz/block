import '../block.dart';
import 'web/web_block.dart';

Block createBlock(List<Object> parts, {String type = ''}) =>
    createWebBlock(parts, type: type);
