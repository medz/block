# block

[![Pub Version](https://img.shields.io/pub/v/block.svg)](https://pub.dev/packages/block)
[![Tests Status](https://github.com/medz/block/actions/workflows/test.yml/badge.svg)](https://github.com/medz/block/actions/workflows/test.yml)

`block` provides a Blob-style immutable binary data API for Dart.

## Design

- One minimal, Blob-compatible API surface.
- `web`: wraps native browser `Blob` via [`package:web`](https://pub.dev/packages/web).
- `io`: stores block data in temp files and uses finalizers for cleanup.
- `slice()` strategy on `io`:
  - `<= 64KB`: copy to a new temp file
  - `> 64KB`: share backing file with offset/length view

## Installation

```bash
dart pub add block
```

## API

```dart
import 'package:block/block.dart';

Future<void> main() async {
  final block = Block([
    'hello ',
    'world',
  ], type: 'text/plain');

  final size = block.size;
  final type = block.type;

  final bytes = await block.arrayBuffer();
  final text = await block.text();

  final slice = block.slice(0, 5);

  await for (final chunk in block.stream(chunkSize: 1024)) {
    // handle chunk
  }
}
```

Supported constructor part types:

- `String`
- `Uint8List`
- `ByteData`
- `Block`

## Breaking Reset in 1.0.0

This release intentionally removes the previous memory/cache/dedup framework APIs and keeps only the Blob-style core contract.

## License

BSD-style. See [LICENSE](LICENSE).
