// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'block.dart';

/// 表示一个可以延迟执行的操作
///
/// 这个类允许定义操作但推迟执行，只有在真正需要结果时才执行。
/// 这种方式可以优化性能，避免不必要的计算。
abstract class DeferredOperation<T> {
  /// 执行操作并返回结果
  Future<T> execute();

  /// 获取操作的类型描述
  String get operationType;
}

/// 延迟文本解码操作
class DeferredTextDecoding extends DeferredOperation<String> {
  final Block _block;
  final Encoding _encoding;

  DeferredTextDecoding(this._block, this._encoding);

  @override
  Future<String> execute() async {
    final data = await _block.arrayBuffer();
    return _encoding.decode(data);
  }

  @override
  String get operationType => 'TextDecoding';
}

/// 延迟Block合并操作
class DeferredBlockMerge extends DeferredOperation<Block> {
  final List<Block> _blocks;
  final String _type;

  DeferredBlockMerge(this._blocks, this._type);

  @override
  Future<Block> execute() async {
    // 收集所有块的数据
    final List<Uint8List> allData = [];
    for (final block in _blocks) {
      allData.add(await block.arrayBuffer());
    }

    // 创建新的合并Block
    return Block(allData, type: _type);
  }

  @override
  String get operationType => 'BlockMerge';
}

/// 延迟数据转换操作
class DeferredDataTransformation<T> extends DeferredOperation<T> {
  final Block _block;
  final Future<T> Function(Uint8List data) _transformer;
  final String _transformType;

  DeferredDataTransformation(
    this._block,
    this._transformer,
    this._transformType,
  );

  @override
  Future<T> execute() async {
    final data = await _block.arrayBuffer();
    return _transformer(data);
  }

  @override
  String get operationType => 'DataTransformation:$_transformType';
}

/// 延迟操作工厂类，用于创建各种延迟操作
class DeferredOperations {
  /// 创建延迟文本解码操作
  static DeferredTextDecoding text(Block block, {Encoding encoding = utf8}) {
    return DeferredTextDecoding(block, encoding);
  }

  /// 创建延迟合并操作
  static DeferredBlockMerge merge(List<Block> blocks, {String type = ''}) {
    return DeferredBlockMerge(blocks, type);
  }

  /// 创建通用延迟数据转换操作
  static DeferredDataTransformation<T> transform<T>(
    Block block,
    Future<T> Function(Uint8List data) transformer,
    String transformType,
  ) {
    return DeferredDataTransformation<T>(block, transformer, transformType);
  }
}
