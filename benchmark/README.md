# Block Benchmarks

Run all benchmarks:

```bash
dart benchmark/run_all.dart
```

Current benchmark suite covers:

- Block creation (single part and multipart)
- Slice behavior (copy path and shared path)
- `arrayBuffer()`, `text()`, and `stream()` throughput
- Composition from nested `Block` parts
