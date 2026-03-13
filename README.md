# block

[![Pub Version](https://img.shields.io/pub/v/block.svg)](https://pub.dev/packages/block)
[![Tests Status](https://github.com/medz/block/actions/workflows/test.yml/badge.svg)](https://github.com/medz/block/actions/workflows/test.yml)

`block` provides a Blob-style immutable binary data API for Dart.

## Design

- One minimal, Blob-compatible API surface.
- `web`: wraps native browser `Blob` via [`package:web`](https://pub.dev/packages/web).
- `io`: keeps small byte-only blocks in memory and lazily materializes larger/composed blocks to temp files (finalizer cleanup).
- `stream()` is the primary lazy read path; `arrayBuffer()` is the explicit materialized read path.
- `Block` parts are resolved lazily for `io` composed blocks: bytes are fetched/materialized on first read (`arrayBuffer`/`text`).
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

For downstream runtimes and fetch-style abstractions, prefer `stream()` when
you want to preserve a lazy pipeline. `arrayBuffer()` intentionally
materializes the entire block in memory.

### VM File-Backed Blocks

On `dart:io`, you can open a file directly as a lazy `Block`:

```dart
import 'dart:io';
import 'package:block/io.dart';

Future<void> main() async {
  final block = await FileBlock.open(
    File('payload.bin'),
    type: 'application/octet-stream',
  );

  final header = block.slice(0, 4096);
  final footer = await FileBlock.openRange(
    File('payload.bin'),
    offset: block.size - 4096,
    length: 4096,
  );

  await for (final chunk in header.stream()) {
    // handle bytes lazily
  }
}
```

`FileBlock` captures the file length when opened and reads from the source file
on demand. Callers must treat the underlying file as immutable while a block
view is in use.

Supported constructor part types:

- `String`
- `Uint8List`
- `ByteData`
- `File` on `dart:io`
- `Block`

Additional web-only part types:

- `web.Blob`
- `web.File`

## Breaking Reset in 1.0.0

This release intentionally removes the previous memory/cache/dedup framework APIs and keeps only the Blob-style core contract.

## License

BSD-style. See [LICENSE](LICENSE).
