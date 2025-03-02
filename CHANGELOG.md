## 0.0.1

_Released: 2023-10-05_

Initial stable release of the Block package.

### Features

- Core `Block` interface with efficient binary data handling
- Multiple construction methods:
  - `Block()` - Create from builder function
  - `Block.empty()` - Create an empty block
  - `Block.fromString()` - Create from strings with encoding support
  - `Block.fromBytes()` - Create from existing Uint8List instances
  - `Block.formStream()` - Create from byte streams
- Data access methods:
  - `size` - Get block size in bytes
  - `stream()` - Access as a Stream<Uint8List>
  - `bytes()` - Get all data as a single Uint8List
  - `text()` - Get data as UTF-8 decoded string
- Slicing API with support for:
  - Positive and negative indices
  - Start and end positions
  - Efficient sub-range access without copying
- Performance optimizations:
  - Lazy initialization
  - Result caching
  - Special handling for large blocks
  - Memory-efficient implementation
- Comprehensive error handling and validation

### Implementation Details

- Memory-efficient processing of binary data
- Automatic caching of results for improved performance
- UTF-8 decoding with fallback for malformed sequences
- Proper resource management for stream-based blocks

This is the first stable release, providing a solid foundation for efficient binary data handling in Dart applications.
