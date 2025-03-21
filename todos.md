# Block 实现进度与待办事项

## 已完成工作

### 研究与分析

- [x] 研究 WebKit 中的 Blob 实现
- [x] 分析核心实现文件和架构
- [x] 理解 WebKit 中 Blob 的内存管理机制
- [x] 分析 WebKit 中 Blob 分片的实现方式
- [x] 整理分析结果到文档
- [x] 内存管理机制分析与报告
- [x] 分析 Dart 中 Expando 和 WeakReference 在内存管理中的应用

### 设计

- [x] 设计纯 Dart 版本的 Block 架构
- [x] 确定核心类结构与关系
- [x] 定义内存管理与优化策略
- [x] 设计 API 接口
- [x] 设计分段存储策略

### 实现

- [x] 实现核心 Block 类
  - [x] 与 Web API Blob 兼容的构造函数
  - [x] 支持多种数据源（String, Uint8List, ByteData, Block）
  - [x] size 和 type 属性
  - [x] slice() 方法支持（与 Blob.slice 兼容）
  - [x] arrayBuffer() 方法支持（与 Blob.arrayBuffer 兼容）
  - [x] text() 方法支持（与 Blob.text 兼容）
  - [x] 专用于 Dart 的 stream() 方法
- [x] 删除早期的类设计
  - [x] 移除 BlockBuilder 类
  - [x] 移除 BlockPart 类及其子类
  - [x] 直接在 Block 类内部处理数据转换
- [x] 更新库结构
  - [x] 简化 API 导出
  - [x] 移除不必要的文件
  - [x] 将 ByteDataView 拆分到独立文件
- [x] 实现分段存储策略，处理大型二进制数据
- [x] 实现内存管理器和可释放块
  - [x] 创建 MemoryManager 类进行内存监控
  - [x] 实现 DisposableBlock 类提供显式内存释放机制
  - [x] 基于弱引用的块跟踪系统
  - [x] LRU 清理策略
  - [x] 使用 Dart 原生 WeakReference 替代自定义实现
  - [x] 应用 Finalizer 在对象被回收时执行清理操作
- [x] 高效数据存储策略
  - [x] 为大型数据实现分段内存管理
  - [x] 优化内存布局减少碎片
  - [x] 优化分块大小策略
- [x] 零拷贝与引用优化（部分）
  - [x] 分片时只保存引用和范围信息
  - [x] 避免数据复制提高性能
  - [x] 优化分片操作的内存效率
  - [x] 实现完整的零拷贝操作机制
- [x] 内存追踪与压力响应
  - [x] 实现引用计数机制
  - [x] 追踪内存使用成本
  - [x] 添加内存使用报告功能
  - [x] 添加内存压力响应机制
- [x] 缓存与内存释放策略（部分）
  - [x] 实现缓存机制
  - [x] 为常用操作实现缓存池
  - [x] 实现缓存过期策略
  - [x] 根据内存压力级别智能释放内存
    - [x] 轻度压力下清理非关键缓存
    - [x] 中度压力下清理所有缓存
    - [x] 高度压力下强制释放所有可能的内存
- [x] 数据去重与共享
  - [x] 实现数据去重（相同内容只存储一次）
  - [x] 优化引用计数机制
  - [x] 实现数据块共享机制
- [x] 惰性计算与延迟处理
  - [x] size 属性惰性计算
  - [x] 延迟加载策略，仅在需要时加载数据
  - [x] 推迟操作执行到实际需要时
    - [x] WebKit 的 Blob 实现中使用了 Promise 和异步方式推迟操作执行
    - [x] 实现 DeferredOperation 系统，提供更灵活的延迟执行机制
    - [x] 关键操作推迟到真正需要结果时执行
    - [x] 添加操作链和自定义转换器功能

### 测试

- [x] 测试基本创建功能
- [x] 测试从多种数据源创建 Block
- [x] 测试分片功能
- [x] 测试负数索引的分片
- [x] 测试 arrayBuffer() 方法
- [x] 测试 text() 方法
- [x] 测试 stream() 方法
- [x] 测试边缘情况处理
- [x] 测试内存使用和去重功能
- [x] 测试内存管理器功能
- [x] 建立基准测试框架
- [x] 修复"Block creates from list of parts"测试
- [x] 修复"Block throws on unsupported part types"测试
- [x] 修复"Data Deduplication identical data blocks are stored only once"测试
- [x] 修复"Data Deduplication large data blocks utilize deduplication"测试
- [x] 修复处理嵌套 Block 时的问题
- [x] 修复 Block 构造函数中对不支持类型的异常处理
- [x] 解决 benchmark 中的 block 对象引用问题

### 文档

- [x] 更新 README 示例
- [x] 添加与 Web API Blob 兼容的用法示例
- [x] 更新大文件处理示例
- [x] 改进性能考虑部分说明
- [x] 添加内存管理改进文档

## 待办事项（按优先级）

### 第一阶段：核心内存管理问题（高优先级，1-2 周）

1. **重构 MemoryManager**

   - [x] 使用 Dart 原生 WeakReference 替代自定义实现
   - [x] 应用 Finalizer 在对象被回收时执行清理操作
   - [x] 更新内存管理代码以优化引用跟踪
   - [x] 改进 \_DataStore 实现，更准确地追踪数据块引用
   - [x] 创建内存管理集成计划文档
   - [x] 实现 Block 类与 MemoryManager 的低侵入性集成
   - [x] 添加内存管理集成测试用例
   - [ ] 优化内存清理策略，确保在不同内存压力下都能高效工作
   - [ ] 提供更详细的内存使用统计和诊断信息

2. **修复 DisposableBlock 问题**

   - [ ] 分析 FormatException: Unexpected extension byte 错误原因
   - [ ] 修复 DisposableBlock 异步操作 UTF-8 解码错误
   - [ ] 改进文本解码机制
   - [ ] 完善异步操作错误处理

3. **解决关键测试失败问题**
   - [ ] 修复"内存优化测试 内存监控器会增加内存使用而不释放"问题
   - [ ] 确保清理操作能实际减少内存使用量
   - [ ] 修复 DisposableBlock 异步操作测试失败问题
   - [ ] 修复 memory_optimization_test.dart 中的\_DataStore 未定义错误
   - [ ] 解决变量赋值为 null 的类型问题
   - [ ] 验证内存管理集成在各种场景下的正常工作
     - [ ] 单元测试验证 Block 对象的生命周期管理
     - [ ] 压力测试验证大量 Block 对象的内存管理
     - [ ] 长时间运行测试验证内存稳定性
   - [ ] 实施内存管理集成测试计划
     - [ ] 实现基本引用跟踪测试，验证 MemoryManager 是否正确跟踪 Block 访问
     - [ ] 实现内存清理测试，验证垃圾回收后的资源释放
     - [ ] 实现 DisposableBlock 显式释放测试，确认内存减少
     - [ ] 实现孤立数据清理测试，验证无引用数据块的清理
     - [ ] 实现内存压力测试，验证不同内存压力级别下的清理响应
     - [ ] 实现长时间运行稳定性测试，确保内存不会无限增长
     - [ ] 实现性能测试，验证内存管理对关键操作性能的影响

### 第二阶段：去重和内存优化（中优先级，2-3 周）

1. **解决去重计数不准确问题**

   - [ ] 修复重复块计数异常（预期 1 个，实际 12 个）
   - [ ] 修复不同数据块被错误识别为重复问题（预期 0 个，实际 24 个）
   - [ ] 优化去重算法或哈希计算方法
   - [ ] 确保数据去重功能正确统计内存节省

2. **改进内存释放策略**

   - [ ] 优化 LRU 策略实现
   - [ ] 调整清理触发阈值
   - [ ] 实现更精确的数据块引用计数
   - [ ] 解决内存增长问题
     - [ ] 修复添加相同数据块后内存增长过快问题
     - [ ] 确保相同数据只存储一份

3. **内存使用监控与分析**
   - [ ] 修复基准测试中内存统计显示为 0 的问题
   - [ ] 检查并修复内存统计功能
   - [ ] 优化测试结果数据收集
   - [ ] 增强监控和诊断功能

### 第三阶段：性能优化与测试（中低优先级，3-4 周）

1. **性能分析与优化**

   - [ ] 关键路径性能分析
   - [ ] 内存使用测试
   - [ ] 实施性能优化措施
   - [ ] 针对 Dart VM 优化内存管理
   - [ ] 评估内存管理集成对性能的影响
     - [ ] 测量内存管理代码在关键操作上的性能开销
     - [ ] 优化高频调用路径中的内存管理操作
     - [ ] 实现可配置的内存管理策略，平衡性能和内存占用
     - [ ] 建立性能基准测试套件，用于持续监控性能变化
     - [ ] 分析并优化内存分配和垃圾回收频率
     - [ ] 测量并减少引用跟踪操作的开销
     - [ ] 优化异步操作的内存和性能表现

2. **完善测试覆盖**

   - [ ] 添加更多边缘情况测试
   - [ ] 修复其他测试失败问题
   - [ ] 添加压力测试和长时间运行测试
   - [ ] 跨平台测试（Web、移动、桌面）
   - [ ] 实现全面的内存管理测试套件
     - [ ] 创建模拟测试环境，能够可靠地触发垃圾回收
     - [ ] 添加并发测试，验证多线程环境下的内存管理行为
     - [ ] 实现内存泄漏检测测试，确保长时间运行不会有累积的内存增长
     - [ ] 编写故障注入测试，验证异常情况下的内存管理行为
     - [ ] 添加极端情况测试（非常大的块、非常多的块）
     - [ ] 实现内存管理与不同数据类型集成的测试用例
     - [ ] 建立持续集成中的内存监控基准

3. **文档完善**
   - [ ] 编写详细的 API 文档
   - [ ] 更新内存管理说明
   - [ ] 添加内存优化最佳实践
   - [ ] 编写性能优化指南

### 未来规划（低优先级）

1. **功能扩展**

   - [ ] 文件系统集成

     - [ ] 实现基于 dart:io 的文件支持（可选导入）
     - [ ] 从文件创建 Block 的便捷方法
     - [ ] 高效处理超大文件
     - [ ] 优化大文件流式处理

   - [ ] 数据处理扩展
     - [ ] type 属性规范化处理
     - [ ] base64 编码支持
     - [ ] URL 创建支持（类似于 URL.createObjectURL）
     - [ ] 数据压缩/解压缩支持
     - [ ] 可选的加密/解密支持

2. **平台特定优化**

   - [ ] Web 平台优化
     - [ ] 在 Web 平台上使用原生 Blob 对象
     - [ ] 提供与浏览器 Blob API 的无缝互操作性
   - [ ] Flutter/Dart 特定优化
     - [ ] 优化与 Flutter 图像处理的集成
     - [ ] 与 Flutter IO 操作的高效集成

3. **生态系统集成**
   - [ ] 与其他常用 Dart 库的无缝集成
   - [ ] 提供专用于 Flutter 的优化版本
   - [ ] 开发 Firebase 存储集成

## 当前内存管理问题分析

根据内存管理测试结果分析，我们发现了以下问题需要解决：

### 1. 内存监控器不能有效释放内存

- 内存监控器可以检测到内存使用情况，但不能有效释放内存
- 即使在执行清理操作后，内存使用量仍然保持在高水平
- 需要重新评估清理策略，确保不再使用的数据块能够被正确识别和释放
- 重构 MemoryManager，使用 Dart 原生 WeakReference 和 Finalizer

### 2. 去重功能计数异常

- 去重测试显示重复块计数与预期不符，实际计数远高于预期
- 相同数据块测试：预期 1 个重复块，实际 12 个
- 不同数据块测试：预期 0 个重复块，实际 24 个
- 可能是哈希计算或引用计数机制存在问题

### 3. DisposableBlock 异步操作 UTF-8 解码错误

- DisposableBlock 的异步文本处理测试失败
- 错误信息：`FormatException: Unexpected extension byte (at offset 128)`
- 需要检查文本编码/解码处理逻辑

### 4. 内存增长问题

- 添加相同数据块后，内存增长速度快于预期
- 简单去重测试中，添加 10 个相同数据块后，内存增加了 1025200 字节，超出预期的 512000 字节
- 需要确保相同数据确实只存储一份，并优化内存分配策略

### 5. 基准测试中的内存管理问题

- 即使使用了 addBlockReference()方法，测试仍然显示存在潜在的内存问题
- Block 创建测试显示内存使用量随着块数量增加而线性增长，没有体现出去重的优势
