# Block

[![Pub Version](https://img.shields.io/pub/v/block.svg)](https://pub.dev/packages/block)
[![Tests Status](https://github.com/medz/block/actions/workflows/test.yml/badge.svg)](https://github.com/medz/block/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A flexible and efficient binary data block handling library for Dart.

## Features

- Efficient handling of binary data blocks
- Stream-based API for memory efficiency
- Lazy loading to minimize memory usage
- Built-in caching for performance optimization
- Support for slicing without copying data
- UTF-8 text decoding with error handling
- Data deduplication for memory optimization

## Installation

You can install the package from the command line:

```bash
dart pub add block
```

## Usage

### Creating Blocks

Create a block from various sources:

```dart
import 'package:block/block.dart';
import 'dart:typed_data';

// Basic usage - similar to Web API's Blob constructor
final block = Block([
  'Hello, ',
  Uint8List.fromList([119, 111, 114, 108, 100]), // "world" in UTF-8
  '!'
], type: 'text/plain');

// Block from a single Uint8List
final binaryBlock = Block([Uint8List.fromList([1, 2, 3, 4, 5])]);

// Block from ByteData
final buffer = Uint8List(4).buffer;
final byteData = ByteData.view(buffer)..setInt32(0, 42);
final byteDataBlock = Block([byteData]);

// Empty block
final emptyBlock1 = Block([]);
// Or using the convenience method
final emptyBlock2 = Block.empty(type: 'application/octet-stream');
```

### Accessing Data

Access the data in various formats:

```dart
// Get the size in bytes
final size = block.size;

// Get the MIME type
final type = block.type;

// Get as a complete Uint8List (corresponds to Blob.arrayBuffer())
final bytes = await block.arrayBuffer();

// Get as a string (UTF-8 decoded) (corresponds to Blob.text())
final text = await block.text();

// Get as a stream of chunks (Dart-specific addition)
await for (final chunk in block.stream(chunkSize: 1024)) {
  // Process each chunk
}
```

### Slicing

Extract sub-ranges of data without copying the entire block:

```dart
// Get bytes from index 5 to 9 (inclusive of 5, exclusive of 10)
final slice = block.slice(5, 10);

// Omit end index to slice to the end
final toEnd = block.slice(5);

// Use negative indices to count from the end
// For a block of size 10, this gets the last 5 bytes (indices 5-9)
final lastFive = block.slice(-5);
// For a block of size 10, this gets bytes from index 0 to index 7 (exclusive)
final exceptLastTwo = block.slice(0, -2);

// Specify a different content type for the slice
final htmlSlice = block.slice(0, 100, 'text/html');
```

### Example: Processing a Large File

```dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:block/block.dart';

Future<void> processLargeFile(String path) async {
  final file = File(path);
  final fileSize = await file.length();

  // Read the file into memory - in a real app, you might want to use a more
  // memory-efficient approach for very large files
  final fileData = await file.readAsBytes();

  // Create a block from the file data
  final block = Block([fileData]);

  // Process the first 1MB
  final header = block.slice(0, 1024 * 1024);
  final headerText = await header.text();
  print('File header: $headerText');

  // Process the file in chunks
  final chunkSize = 10 * 1024 * 1024; // 10MB chunks
  final chunksCount = (fileSize / chunkSize).ceil();

  for (int i = 0; i < chunksCount; i++) {
    final start = i * chunkSize;
    final end = (start + chunkSize) > fileSize ? fileSize : start + chunkSize;

    final chunk = block.slice(start, end);
    final chunkData = await chunk.arrayBuffer();
    print('Processed chunk ${i + 1}/$chunksCount: ${chunkData.length} bytes');

    // Do something with the chunk data...
  }
}
```

## Performance Considerations

- Blocks are lazily initialized and only allocate memory when needed
- The `arrayBuffer()` and `text()` methods return cached results for subsequent calls
- Slicing operations don't copy data until the slice content is actually accessed
- For blocks larger than 10MB, special handling is used to optimize memory usage
- The `stream()` method provides efficient access to large blocks without loading the entire content into memory at once
- Data deduplication automatically stores identical data blocks only once, reducing memory usage

### Data Deduplication

The Block library automatically detects and optimizes storage of identical data blocks:

```dart
// These blocks contain identical data but only store it once in memory
final block1 = Block([Uint8List.fromList([1, 2, 3, 4, 5])]);
final block2 = Block([Uint8List.fromList([1, 2, 3, 4, 5])]);

// Check deduplication statistics
final stats = Block.getDataDeduplicationReport();
print('Memory saved: ${stats['totalSavedMemory']} bytes');
print('Duplicate blocks: ${stats['duplicateBlockCount']}');

// Get just the memory savings
final savedMemory = Block.getDataDeduplicationSavedMemory();
print('Memory saved: $savedMemory bytes');

// Get just the duplicate count
final duplicateCount = Block.getDataDeduplicationDuplicateCount();
print('Duplicate blocks: $duplicateCount');
```

The deduplication system:

- Automatically identifies identical data blocks using efficient hashing
- Stores each unique data block only once in memory
- Maintains reference counting to properly manage the lifecycle of shared data
- Releases unused data blocks when they are no longer referenced
- Works transparently without requiring any special API calls

## API Reference

See the [API Documentation](https://pub.dev/documentation/block/latest/) for detailed information about all classes and methods.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please make sure to update tests as appropriate and adhere to the existing coding style.

## License

This package is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgements

- Inspired by the [Blob](https://developer.mozilla.org/en-US/docs/Web/API/Blob) API from the Web platform
- Thanks to all contributors who have helped shape this library

---

<p align="center">Made with ❤️ By</p>
<p align="center">
  <a href="https://github.com/medz/block/graphs/contributors">
    <img src="https://contrib.rocks/image?repo=medz/block" alt="Contributors" />
  </a>
</p>

## 性能考虑

Block 库设计了以下几个优化点：

1. **高效内存使用**: Block 采用分段存储策略，特别适合处理大型二进制数据。对于大于 1MB 的数据，会自动拆分为多个数据块进行存储，减少内存碎片并优化内存使用。

2. **延迟操作**: 创建 Block 或调用`slice()`方法时，Block 并不会立即复制数据。只有在实际需要获取完整数据内容时（如调用`arrayBuffer()`）才会执行数据复制操作。

3. **流式处理**: 对于大型数据，可以使用`stream()`方法以较小的块进行处理，避免一次性加载全部内容到内存中。

4. **无复制切片**: 使用引用计数机制，`slice()`操作只保存对原始数据的引用和偏移量，避免不必要的数据复制。
