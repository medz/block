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

// From a builder function
final block = Block((updates) {
  updates(Uint8List.fromList([1, 2, 3]));
  updates(Uint8List.fromList([4, 5, 6]));
});

// From strings
final textBlock = Block.fromString(['Hello', ' ', 'World']);

// From Uint8List instances
final bytesBlock = Block.fromBytes([
  Uint8List.fromList([1, 2, 3]),
  Uint8List.fromList([4, 5, 6]),
]);

// From a stream
final streamBlock = Block.formStream(
  someStream, // Stream<Uint8List>
  expectedSize, // int
);

// Empty block
final emptyBlock = Block.empty();
```

### Accessing Data

Access the data in various formats:

```dart
// Get the size in bytes
final size = block.size;

// Get as a stream of chunks
await for (final chunk in block.stream()) {
  // Process each chunk
}

// Get as a complete Uint8List
final bytes = await block.bytes();

// Get as a string (UTF-8 decoded)
final text = await block.text();
```

### Slicing

Extract sub-ranges of data without copying the entire block:

```dart
// Get bytes 5-9 (inclusive of 5, exclusive of 10)
final slice = block.slice(5, 10);

// Omit end index to slice to the end
final toEnd = block.slice(5);

// Use negative indices to count from the end
final lastFive = block.slice(-5);
final exceptLastTwo = block.slice(0, -2);
```

### Example: Processing a Large File

```dart
import 'dart:io';
import 'package:block/block.dart';

Future<void> processLargeFile(String path) async {
  final file = File(path);
  final fileSize = await file.length();

  // Create a block from the file's content
  final block = Block.formStream(file.openRead(), fileSize);

  // Process the first 1MB
  final header = block.slice(0, 1024 * 1024);
  final headerText = await header.text();
  print('File header: $headerText');

  // Process the file in chunks of 10MB
  final chunkSize = 10 * 1024 * 1024;
  for (int i = 0; i < fileSize; i += chunkSize) {
    final end = (i + chunkSize < fileSize) ? i + chunkSize : fileSize;
    final chunk = block.slice(i, end);

    // Process each chunk
    final chunkBytes = await chunk.bytes();
    print('Processed chunk ${i ~/ chunkSize + 1}: ${chunkBytes.length} bytes');
  }
}
```

## Performance Considerations

- Blocks are lazily initialized and only allocate memory when needed
- The `bytes()` and `text()` methods cache their results for subsequent calls
- Slicing operations don't copy data until the slice content is actually accessed
- For blocks larger than 10MB, special handling is used to optimize memory usage

## Stream-Based Blocks

When creating blocks from streams, keep in mind:

- The stream will be consumed when the block is accessed
- Non-broadcast streams can only be consumed once
- The stream's total byte count must match the specified size
- Once consumed, the data is cached for future access

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
