# Block 库内存管理改进

## 概述

为了解决 Block 库中发现的内存管理问题，我们实现了以下改进：

1. **内存管理器 (MemoryManager)**：一个专门的内存管理组件，负责跟踪和清理不再使用的数据块。
2. **可释放块 (DisposableBlock)**：Block 的包装类，提供显式内存释放机制。
3. **引用跟踪**：使用弱引用和访问时间跟踪来识别可以安全释放的数据块。

## 主要组件

### MemoryManager

内存管理器是一个单例类，提供以下功能：

- **块引用跟踪**：使用弱引用跟踪 Block 对象，当对象被垃圾回收时可以检测到。
- **访问时间跟踪**：记录每个数据块的最后访问时间，用于实现 LRU（最近最少使用）清理策略。
- **周期性内存检查**：定期检查内存使用情况，在内存压力大时触发清理。
- **多级内存阈值**：支持设置高水位和临界水位，根据内存压力程度采取不同的清理策略。

### DisposableBlock

可释放块是 Block 的包装类，提供与 Block 相同的 API，但增加了显式内存管理功能：

- **显式释放**：通过`dispose()`方法允许开发者主动释放不再需要的块。
- **自动注册**：创建时自动向内存管理器注册，便于跟踪。
- **访问记录**：每次访问块时记录访问时间，用于 LRU 策略。
- **状态检查**：防止使用已释放的块，提供清晰的错误信息。

## 使用方法

### 基本用法

```dart
import 'package:block/block.dart';

void main() {
  // 启动内存管理器
  MemoryManager.instance.start(
    highWatermark: 100 * 1024 * 1024, // 100MB
    criticalWatermark: 200 * 1024 * 1024, // 200MB
  );

  // 创建可释放块
  final block = DisposableBlock([data]);

  // 使用块...
  final size = block.size;
  final bytes = block.toUint8List();

  // 当不再需要时释放
  block.dispose();
}
```

### 在长时间运行的应用中

```dart
void processLargeFiles(List<File> files) async {
  for (final file in files) {
    // 创建块处理文件
    final data = await file.readAsBytes();
    final block = DisposableBlock([data]);

    // 处理数据
    await processBlock(block);

    // 处理完成后立即释放
    block.dispose();
  }
}
```

## 实现细节

1. **弱引用实现**：使用 Dart 的`Expando`类实现弱引用，避免阻止垃圾回收。
2. **LRU 策略**：基于访问时间实现 LRU 清理策略，优先释放长时间未访问的块。
3. **周期性清理**：即使没有内存压力，也会定期执行清理，防止长时间累积未使用的数据。
4. **多级清理**：根据内存压力程度执行不同强度的清理，在临界情况下采取更激进的策略。

## 注意事项

- 虽然`DisposableBlock`提供了显式释放机制，但仍建议在不再需要块时将其设为`null`，以便垃圾回收器可以回收相关对象。
- 内存管理器会消耗一定的 CPU 资源进行周期性检查，在资源非常受限的环境中应谨慎使用。
- 对于短期使用的小块数据，标准的`Block`类可能更高效，因为它避免了额外的跟踪开销。
