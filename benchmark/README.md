# Block 基准测试框架

这个目录包含了用于测试 Block 库性能的基准测试框架。

## 框架结构

- `framework.dart`: 定义了基准测试的基础类和工具函数
- `block_creation_benchmark.dart`: 测试 Block 创建操作的性能
- `block_operations_benchmark.dart`: 测试 Block 各种操作的性能
- `deduplication_benchmark.dart`: 测试数据去重功能的性能
- `run_all.dart`: 运行所有基准测试的主程序

## 内存跟踪

框架包含了 `MemoryBenchmark` 抽象类，它可以跟踪测试前后的内存使用情况，包括：

- 内存使用量变化
- 活跃 Block 实例数量
- 峰值内存使用

## 测试数据生成

`TestDataGenerator` 类提供了生成测试数据的工具方法：

- `generateRandomData`: 生成随机数据
- `generateSequentialData`: 生成顺序数据
- `generateDuplicateData`: 生成包含重复模式的数据

## 运行基准测试

要运行所有基准测试，请执行：

```bash
dart benchmark/run_all.dart
```

要运行特定的基准测试，可以直接执行对应的文件：

```bash
dart benchmark/block_creation_benchmark.dart
dart benchmark/block_operations_benchmark.dart
dart benchmark/deduplication_benchmark.dart
```

## 添加新的基准测试

要添加新的基准测试，请继承 `MemoryBenchmark` 类并实现 `setUp` 和 `run` 方法。例如：

```dart
class MyNewBenchmark extends MemoryBenchmark {
  MyNewBenchmark() : super('My New Benchmark');

  @override
  void setUp() {
    super.setUp();
    // 初始化测试数据
  }

  @override
  void run() {
    // 执行要测试的操作
  }
}
```

然后将新的基准测试添加到相应的测试文件中。

## 注意事项

- `benchmark_harness` 库不支持异步测试，所以我们只能测量同步操作的性能
- 对于异步操作，我们只测量同步部分的性能
- 内存使用统计依赖于 Block 类中的 `totalMemoryUsage` 和 `activeBlockCount` 静态属性
