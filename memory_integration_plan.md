# Block 库与 MemoryManager 集成计划

## 当前状态

我们已经实现了 `MemoryManager` 类，具有以下功能：

1. 使用 Dart 原生 `WeakReference` 跟踪 Block 对象
2. 使用 `Finalizer` 在 Block 对象被垃圾回收时执行清理操作
3. 实现了数据块与 Block 对象的关联跟踪
4. 提供了内存使用报告和清理策略

然而，我们在将其与 Block 类和 \_DataStore 集成时遇到了一些编译问题，主要涉及：

1. Block 类结构的复杂性和现有代码的限制
2. \_blockId 属性的初始化和使用
3. 分片操作和数据处理的现有实现

## 集成策略

我们将采用以下策略来完成集成：

### 第一阶段：改进 \_DataStore 实现

1. 修改 `_DataStore.store` 和 `_DataStore.release` 方法，使其能够与 MemoryManager 交互
2. 添加数据块 ID 生成和跟踪机制
3. 实现孤立数据清理功能

### 第二阶段：最小化修改 Block 类

由于 Block 类结构复杂，我们将采用最小化修改原则：

1. 确保 Block 构造函数生成唯一的 blockId
2. 在关键访问点添加对 MemoryManager 的访问记录调用
3. 在数据处理和释放点添加与 MemoryManager 的集成

### 第三阶段：测试和优化

1. 创建专门的测试用例验证内存管理集成
2. 测量和优化内存使用情况
3. 确保在不同场景下内存管理正常工作

## 详细设计

### \_DataStore 改进

```dart
// _DataStore 类内的方法改进

// 存储数据并关联到 Block（如果提供）
Uint8List store(Uint8List data, {Block? sourceBlock}) {
  // 现有逻辑...

  // 如果提供了 sourceBlock，关联数据与 Block
  if (sourceBlock != null) {
    final blockId = sourceBlock.hashCode.toString();
    final dataId = hash; // 或生成的特定哈希

    // 通知 MemoryManager 关联数据与 Block
    MemoryManager.instance.associateDataWithBlock(
      blockId,
      dataId,
      data.length,
    );
  }

  // 返回数据...
}

// 释放数据并解除与 Block 的关联（如果提供）
void release(Uint8List data, {Block? sourceBlock}) {
  // 现有逻辑...

  // 如果提供了 sourceBlock，解除数据与 Block 的关联
  if (sourceBlock != null) {
    final blockId = sourceBlock.hashCode.toString();
    final dataId = hash; // 或识别的哈希

    // 通知 MemoryManager 解除数据与 Block 的关联
    MemoryManager.instance.dissociateDataFromBlock(
      blockId,
      dataId,
      data.length,
    );
  }

  // 减少引用计数并可能移除数据...
}

// 清理不再被任何 Block 引用的数据
int cleanOrphanedData() {
  int freedBytes = 0;
  final keysToRemove = <String>[];

  // 查询 MemoryManager 获取每个数据块的引用状态
  for (final entry in _store.entries) {
    final dataId = entry.key;
    if (MemoryManager.instance.getDataReferenceCount(dataId) <= 0) {
      keysToRemove.add(dataId);
      freedBytes += entry.value.data.length;
    }
  }

  // 移除未引用的数据
  for (final key in keysToRemove) {
    _store.remove(key);
  }

  return freedBytes;
}
```

### Block 类集成点

在 Block 类中，我们将在以下关键点添加与 MemoryManager 的集成：

1. 在构造函数中注册 Block：

```dart
Block(...) {
  // 现有初始化...

  // 使用对象的 hashCode 作为唯一标识符
  final blockId = hashCode.toString();

  // 注册到 MemoryManager
  MemoryManager.instance.registerBlock(this, blockId);
}
```

2. 在关键访问方法中记录访问：

```dart
int get size {
  // 记录访问
  MemoryManager.instance.recordBlockAccess(hashCode.toString());

  // 现有逻辑...
}

Stream<Uint8List> stream() {
  // 记录访问
  MemoryManager.instance.recordBlockAccess(hashCode.toString());

  // 现有逻辑...
}
```

3. 在数据处理方法中使用 sourceBlock 参数：

```dart
void _processData() {
  // 在调用 _DataStore.store 时传递 this 作为 sourceBlock
  final storedData = _DataStore.instance.store(bytes, sourceBlock: this);

  // 现有逻辑...
}
```

## 实施计划

1. 首先实现 \_DataStore 的改进
2. 添加测试用例验证 \_DataStore 与 MemoryManager 的集成
3. 逐步添加 Block 类的集成点，每次添加后进行测试
4. 最后实现完整的内存使用监控和报告功能

## 注意事项

1. 保持对现有功能的兼容性
2. 避免引入性能开销
3. 确保内存管理逻辑不会导致内存泄漏
4. 提供清晰的文档说明内存管理的行为和最佳实践
