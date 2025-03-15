// Copyright (c) 2023, the Block project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:block/block.dart';
import 'package:test/test.dart';

void main() {
  group('ByteDataView', () {
    test('basic operations', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final view = ByteDataView([data], 5);

      // 测试基本属性
      expect(view.length, equals(5));
      expect(view.isContinuous, isTrue);

      // 测试字节访问
      expect(view.getUint8(0), equals(1));
      expect(view.getUint8(4), equals(5));
      expect(() => view.getUint8(5), throwsRangeError);

      // 测试子视图
      final subView = view.subView(1, 4);
      expect(subView.length, equals(3));
      expect(subView.getUint8(0), equals(2));
      expect(subView.getUint8(2), equals(4));

      // 测试转换
      final list = view.toUint8List();
      expect(list, equals([1, 2, 3, 4, 5]));

      // 测试连续数据获取
      final direct = view.continuousData;
      expect(direct, isNotNull);
      expect(direct, equals(data));
    });

    test('with multiple chunks', () {
      final chunk1 = Uint8List.fromList([1, 2, 3]);
      final chunk2 = Uint8List.fromList([4, 5, 6]);
      final view = ByteDataView([chunk1, chunk2], 6);

      // 测试基本属性
      expect(view.length, equals(6));
      expect(view.isContinuous, isFalse);

      // 测试字节访问跨块
      expect(view.getUint8(0), equals(1));
      expect(view.getUint8(2), equals(3));
      expect(view.getUint8(3), equals(4));
      expect(view.getUint8(5), equals(6));

      // 测试子视图跨块
      final subView = view.subView(2, 5);
      expect(subView.length, equals(3));
      expect(subView.getUint8(0), equals(3));
      expect(subView.getUint8(1), equals(4));
      expect(subView.getUint8(2), equals(5));

      // 测试转换
      final list = view.toUint8List();
      expect(list, equals([1, 2, 3, 4, 5, 6]));

      // 测试连续数据获取（应为null，因为有多个块）
      final direct = view.continuousData;
      expect(direct, isNull);
    });

    test('buffer getter', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final view = ByteDataView([data], 5);

      // 测试 buffer getter
      final buffer = view.buffer;
      expect(buffer, isA<ByteBuffer>());
      expect(buffer.asUint8List(), equals([1, 2, 3, 4, 5]));
    });

    test('copyTo method', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final view = ByteDataView([data], 5);

      // 测试 copyTo 方法
      final target = Uint8List(10);
      view.copyTo(target, 2);
      expect(target, equals([0, 0, 1, 2, 3, 4, 5, 0, 0, 0]));

      // 测试边界错误情况
      expect(() => view.copyTo(target, -1), throwsRangeError);
      expect(() => view.copyTo(target, 6), throwsRangeError);
    });
  });
}
