# Block 库内存管理集成测试计划

本文档详细描述了 Block 库内存管理集成测试的计划，包括测试目标、测试方法和测试用例。

## 测试目标

1. 验证 MemoryManager, Block 和 \_DataStore 集成的正确性
2. 确保内存管理机制能够有效减少内存泄漏
3. 测试内存压力下的清理机制是否按预期工作
4. 测量内存管理对性能的影响
5. 验证各种场景下的内存使用模式

## 测试范围

1. **基本功能测试**:

   - MemoryManager 块引用跟踪
   - Block 访问记录
   - \_DataStore 数据块引用关联

2. **内存释放测试**:

   - Block 对象垃圾回收时的内存释放
   - DisposableBlock 显式释放的内存管理
   - 孤立数据清理机制

3. **性能测试**:

   - 内存管理操作的性能开销
   - 大量块处理时的内存使用模式
   - 长时间运行测试

4. **边缘情况测试**:
   - 内存压力下的行为
   - 并发创建和访问 Block 对象
   - 异常处理

## 测试用例

### 1. 基本引用跟踪测试

```dart
test('MemoryManager 跟踪 Block 访问', () {
  // 创建一个 Block
  final block = Block([Uint8List(1024 * 100)]); // 100KB 数据
  final blockId = block.hashCode.toString();

  // 验证 Block 已注册到 MemoryManager
  expect(MemoryManager.instance.isBlockReferenced(blockId), isTrue);

  // 访问 Block，记录访问
  block.size;

  // 验证跟踪状态
  expect(MemoryManager.instance.getMemoryReport()['trackedBlockCount'], 1);
  expect(MemoryManager.instance.getEstimatedMemoryUsage(), greaterThan(0));
});
```

### 2. 内存清理测试

```dart
test('内存清理机制', () async {
  // 创建临时 Block 对象
  var blocks = <Block>[];
  for (int i = 0; i < 5; i++) {
    blocks.add(Block([Uint8List(1024 * 100)]));
  }

  // 记录初始状态
  final initialCount = MemoryManager.instance.getTrackedBlockCount();
  final initialMemory = MemoryManager.instance.getEstimatedMemoryUsage();

  // 移除引用，触发垃圾回收
  blocks.clear();
  await _triggerGC();

  // 执行清理
  final freedBytes = MemoryManager.instance.performCleanup();

  // 验证内存减少
  expect(MemoryManager.instance.getTrackedBlockCount(), lessThan(initialCount));
  expect(MemoryManager.instance.getEstimatedMemoryUsage(), lessThan(initialMemory));
});
```

### 3. DisposableBlock 测试

```dart
test('DisposableBlock 显式释放功能', () {
  // 创建 DisposableBlock
  final disposableBlock = DisposableBlock([Uint8List(1024 * 200)]);

  // 记录初始状态
  final initialMemory = MemoryManager.instance.getEstimatedMemoryUsage();

  // 显式释放
  disposableBlock.dispose();

  // 验证内存减少
  expect(() => disposableBlock.size, throwsStateError);
  expect(MemoryManager.instance.getEstimatedMemoryUsage(), lessThan(initialMemory));
});
```

### 4. 孤立数据清理测试

```dart
test('孤立数据块清理', () async {
  // 创建 Block 对象
  Block block = Block([Uint8List(1024 * 100)]);
  block.size; // 确保数据被加载

  // 记录数据块数量
  final initialDataCount = MemoryManager.instance.getTrackedDataCount();

  // 移除对象引用
  block = null;
  await _triggerGC();

  // 执行清理
  MemoryManager.instance.performCleanup();

  // 验证数据块减少
  expect(MemoryManager.instance.getTrackedDataCount(), lessThan(initialDataCount));
});
```

### 5. 内存压力测试

```dart
test('内存压力响应', () {
  // 设置低内存阈值
  MemoryManager.instance.stop();
  MemoryManager.instance.start(
    highWatermark: 2 * 1024 * 1024, // 2MB
    criticalWatermark: 4 * 1024 * 1024, // 4MB
  );

  // 创建大量数据，触发内存压力
  final blocks = <Block>[];
  for (int i = 0; i < 20; i++) {
    blocks.add(Block([Uint8List(1024 * 512)])); // 每个 0.5MB
    blocks[i].size; // 确保数据被加载
  }

  // 验证清理响应
  expect(MemoryManager.instance.getCurrentMemoryPressureLevel(),
         equals(MemoryPressureLevel.high));

  // 内存使用应该低于关键阈值
  expect(MemoryManager.instance.getEstimatedMemoryUsage(),
         lessThan(6 * 1024 * 1024)); // 应该有所清理
});
```

### 6. 长时间运行测试

```dart
test('长时间运行稳定性', () async {
  // 创建和释放大量 Block 对象
  for (int i = 0; i < 10; i++) {
    final blocks = <Block>[];
    for (int j = 0; j < 100; j++) {
      blocks.add(Block([Uint8List(1024 * 10)]));
      blocks[j].size;
    }

    // 记录内存使用
    final memoryUsage = MemoryManager.instance.getEstimatedMemoryUsage();

    // 清除引用
    blocks.clear();
    await _triggerGC();
    MemoryManager.instance.performCleanup();

    // 验证内存不会无限增长
    expect(MemoryManager.instance.getEstimatedMemoryUsage(),
           lessThan(memoryUsage));
  }
});
```

### 7. 性能测试

```dart
test('内存管理性能开销', () {
  // 测量不同操作的性能
  final stopwatch = Stopwatch()..start();

  // 创建Block的性能
  stopwatch.reset();
  final block = Block([Uint8List(1024 * 100)]);
  final createTime = stopwatch.elapsedMicroseconds;

  // 访问操作的性能
  stopwatch.reset();
  block.size;
  final accessTime = stopwatch.elapsedMicroseconds;

  // 分片操作的性能
  stopwatch.reset();
  block.slice(0, 1024);
  final sliceTime = stopwatch.elapsedMicroseconds;

  // 验证性能在合理范围内
  expect(createTime, lessThan(1000)); // 创建应该小于1ms
  expect(accessTime, lessThan(100));  // 访问应该小于0.1ms
  expect(sliceTime, lessThan(500));   // 分片应该小于0.5ms
});
```

## 测试执行计划

1. **准备阶段**:

   - 修复 `memory_optimization_test.dart` 文件中的编译错误
   - 设置测试环境，确保垃圾回收可以被触发
   - 实现辅助方法，用于测量内存使用情况

2. **执行阶段**:

   - 运行基本功能测试，确认引用跟踪正常工作
   - 运行内存清理测试，验证资源回收机制
   - 运行性能测试，确保内存管理不会引入显著开销
   - 运行长时间稳定性测试，确保没有内存泄漏

3. **分析阶段**:
   - 收集测试结果，分析内存使用模式
   - 识别潜在问题和优化机会
   - 根据分析结果调整内存管理策略

## 预期结果

1. 所有功能测试应通过，证明内存管理集成的正确性
2. 内存清理测试应显示内存使用量下降，证明资源回收有效
3. 性能测试应显示内存管理的开销在可接受范围内
4. 长时间运行测试应显示内存使用稳定，没有持续增长

## 后续步骤

1. 实现完整测试套件
2. 修复发现的问题
3. 优化内存管理策略
4. 完善文档，包括内存管理最佳实践和性能注意事项
