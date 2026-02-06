# Block Benchmarks

Benchmarks run in-console only (no artifact files).

The runner uses [`package:coal`](https://pub.dev/packages/coal) for argument parsing and terminal styling.

Run full benchmark suite:

```bash
dart benchmark/run_all.dart
```

Run without ANSI colors:

```bash
dart benchmark/run_all.dart --no-color
```

Coverage:

- Creation (`create/single_part_4kb`, `create/single_part_1mb`)
- Concatenation (`concat/bytes_4x256kb`, `concat/blocks_4x256kb`)
- Slice threshold paths (`slice/copy_64kb`, `slice/share_256kb`)
- Read APIs (`read/array_buffer_8mb`, `read/text_decode_1mb`)
- Stream APIs (`stream/read_8mb_chunk64kb`, `stream/nested_read_4mb_chunk128kb`)
- Composition (`compose/from_nested_blocks_4mb`)

Implementation note:

- High temp-file scenarios are automatically chunked into worker subprocesses to avoid `Too many open files` on environments with low `ulimit -n`.

Metrics printed in console:

- `avg`, `p95`, `p99` with automatic time units (`us`, `ms`, `s`)
- `throughput` for byte-based scenarios with automatic binary units (`B/s`, `KiB/s`, `MiB/s`, ...)
- `temp/iter` based on `block_io_` temp-file delta
- `rss_peak` with automatic binary units (`B`, `KiB`, `MiB`, ...)
