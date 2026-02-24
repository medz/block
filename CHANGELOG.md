## 1.1.0

_Unreleased_

### Added

- Added a small-block in-memory fast path on `io` for byte-only parts up to `64KB`.
- Added shared internal helpers (`BlockBase`, `MemoryBlock`, and shared utilities) to reduce duplicated backend logic.

### Changed

- `io` now avoids temp file materialization for small byte-only blocks.
- `io` keeps lazy temp-file materialization for larger/composed blocks.
- Updated VM/integration tests and docs for the small-block in-memory behavior.

## 1.0.0

_Released: 2026-02-06_

### BREAKING CHANGES

- Reset the package to a minimal Blob-compatible API:
  - `Block(List<Object> parts, {String type = ''})`
  - `size`, `type`, `slice()`, `arrayBuffer()`, `text()`, `stream()`
- Removed legacy memory/cache/dedup/public management APIs.
- Removed legacy helper exports (`MemoryManager`, `DataStore`, `DisposableBlock`, `ByteDataView`, etc.).

### Added

- Platform-specialized implementations under one package via conditional imports.
- `web` implementation that wraps native `Blob` (`package:web`).
- `io` implementation using temp files + finalizer cleanup.
- `io` slice strategy:
  - copy for `<= 64KB`
  - shared backing for `> 64KB`
- New VM/web contract tests and Flutter integration test coverage.

## 0.0.4

_Unreleased_

### Bug Fixes

- Fixed issue with Stream-based blocks when creating multiple slices
- Added caching mechanism to `_StreamBlock` to support multiple accesses to non-broadcast streams
- Updated documentation with best practices for handling large files with streams

### Improvements

- Added data deduplication feature to optimize memory usage when storing identical blocks
- Added public API to view deduplication statistics and memory savings
- Improved memory management under memory pressure conditions
- Added comprehensive tests for stream caching functionality
- Enhanced README examples for processing large files

## 0.0.3

_Released: 2025-03-03_

### Bug Fixes

- Fix typo: renamed `formStream` method to `fromStream` for better API consistency

## 0.0.2

_Released: 2025-03-03_

Improve code comments

## 0.0.1

_Released: 2025-03-02_

Initial stable release of the Block package.
