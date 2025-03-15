// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';
import 'package:block/block.dart';
import 'package:test/test.dart';

void main() {
  group('Deferred Operations Tests', () {
    test('DeferredTextDecoding should delay execution', () async {
      final data = 'Hello, world!';
      final block = Block([data]);

      // 创建延迟操作但不立即执行
      final textOp = block.textOperation();
      expect(textOp.operationType, equals('TextDecoding'));

      // 确认操作没有立即执行（不能直接测试，但我们可以检查类型）
      expect(textOp, isA<DeferredTextDecoding>());

      // 执行操作并验证结果
      final result = await textOp.execute();
      expect(result, equals(data));
    });

    test('Block.text() should internally use deferred operation', () async {
      final data = 'Test deferred execution';
      final block = Block([data]);

      // text()方法内部应该使用DeferredOperation
      final text = await block.text();
      expect(text, equals(data));
    });

    test('DeferredBlockMerge should delay execution', () async {
      final block1 = Block(['First ']);
      final block2 = Block(['block ']);
      final block3 = Block(['merged!']);

      // 创建延迟操作
      final mergeOp = Block.mergeOperation([block1, block2, block3]);
      expect(mergeOp.operationType, equals('BlockMerge'));

      // 执行操作并验证结果
      final mergedBlock = await mergeOp.execute();
      final text = await mergedBlock.text();
      expect(text, equals('First block merged!'));
    });

    test('Block.merge() should internally use deferred operation', () async {
      final block1 = Block(['One, ']);
      final block2 = Block(['two, ']);
      final block3 = Block(['three!']);

      // merge方法内部应该使用DeferredOperation
      final mergedBlock = await Block.merge([block1, block2, block3]);
      final text = await mergedBlock.text();
      expect(text, equals('One, two, three!'));
    });

    test('DeferredDataTransformation should delay execution', () async {
      final data = 'Transform test';
      final block = Block([data]);

      // 创建base64编码延迟操作
      final base64Op = block.transformOperation<String>(
        (data) => Future.value(base64Encode(data)),
        'base64Encoding',
      );
      expect(
        base64Op.operationType,
        equals('DataTransformation:base64Encoding'),
      );

      // 执行操作并验证结果
      final base64Result = await base64Op.execute();
      expect(base64Result, equals(base64Encode(utf8.encode(data))));
    });

    test('transform() should internally use deferred operation', () async {
      final data = 'Testing transform';
      final block = Block([data]);

      // 转换方法内部应该使用DeferredOperation
      final upperCase = await block.transform<String>(
        (data) => Future.value(utf8.decode(data).toUpperCase()),
        'toUpperCase',
      );
      expect(upperCase, equals('TESTING TRANSFORM'));
    });

    test('Deferred operations should properly chain', () async {
      final block1 = Block(['Hello, ']);
      final block2 = Block(['world!']);

      // 创建操作链
      final mergeOp = Block.mergeOperation([block1, block2]);
      final base64Op = (await mergeOp.execute()).transformOperation<String>(
        (data) => Future.value(base64Encode(data)),
        'base64Encoding',
      );

      // 执行最终操作并验证结果
      final base64Result = await base64Op.execute();
      expect(base64Result, equals(base64Encode(utf8.encode('Hello, world!'))));
    });

    test('Operation should only execute when explicitly requested', () async {
      var executionCount = 0;

      // 创建一个可以跟踪执行次数的函数
      Future<String> countingTransformer(Uint8List data) async {
        executionCount++;
        return utf8.decode(data).toUpperCase();
      }

      final block = Block(['count executions']);
      final op = block.transformOperation<String>(
        countingTransformer,
        'countingTransform',
      );

      // 在执行前验证计数器
      expect(executionCount, equals(0));

      // 第一次执行
      final result1 = await op.execute();
      expect(result1, equals('COUNT EXECUTIONS'));
      expect(executionCount, equals(1));

      // 再次执行同一个操作
      final result2 = await op.execute();
      expect(result2, equals('COUNT EXECUTIONS'));
      expect(executionCount, equals(2), reason: '同一个操作再次执行应该再次运行转换函数');
    });
  });
}
