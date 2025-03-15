import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

final _bytesExpando = Expando<Uint8List>('block://cache/bytes');
final _stringExpando = Expando<String>('block://cache/string');

/// Callback function that receives a binary data chunk.
///
/// This is used as a parameter to the [Builder] function to allow
/// adding binary data chunks when constructing a [Block].
typedef Updates = void Function(Uint8List bag);

/// Function that builds a [Block] by adding binary data chunks.
///
/// The [updates] parameter is a callback function that should be called
/// for each binary data chunk to be included in the block.
///
/// Example:
/// ```dart
/// final block = Block((updates) {
///   updates(Uint8List.fromList([1, 2, 3]));
///   updates(Uint8List.fromList([4, 5, 6]));
/// });
/// ```
typedef Builder = void Function(Updates updates);

/// A class representing an efficient container for binary data.
///
/// Block provides a way to handle binary data with memory efficiency and
/// various access patterns. It supports lazy initialization, caching,
/// and slicing operations.
abstract mixin class Block {
  /// Creates a new Block from a builder function.
  ///
  /// The [builder] function receives an update callback that should be called
  /// with each binary data chunk to be included in the block.
  ///
  /// Example:
  /// ```dart
  /// final block = Block((updates) {
  ///   updates(Uint8List.fromList([1, 2, 3]));
  ///   updates(Uint8List.fromList([4, 5, 6]));
  /// });
  /// ```
  factory Block(Builder builder) = _BlockWithBuilder;

  /// Creates an empty Block with size 0.
  ///
  /// Example:
  /// ```dart
  /// final emptyBlock = Block.empty();
  /// assert(emptyBlock.size == 0);
  /// ```
  factory Block.empty() => const _EmptyBlock();

  /// Creates a Block from a collection of strings.
  ///
  /// Each string in [bags] is encoded using the specified [encoding]
  /// (UTF-8 by default) and added to the block.
  ///
  /// Example:
  /// ```dart
  /// final textBlock = Block.fromString(['Hello', ' ', 'World']);
  /// ```
  factory Block.fromString(Iterable<String> bags, {Encoding encoding = utf8}) {
    return Block((updates) {
      for (final bag in bags) {
        updates(encoding.encode(bag).toBytes());
      }
    });
  }

  /// Creates a Block from a collection of byte arrays.
  ///
  /// Each [Uint8List] in [bags] is added to the block.
  ///
  /// Example:
  /// ```dart
  /// final bytesBlock = Block.fromBytes([
  ///   Uint8List.fromList([1, 2, 3]),
  ///   Uint8List.fromList([4, 5, 6])
  /// ]);
  /// ```
  factory Block.fromBytes(Iterable<Uint8List> bags) {
    return Block((updates) {
      for (final bytes in bags) {
        updates(bytes);
      }
    });
  }

  /// Creates a Block from a stream of byte arrays.
  ///
  /// The [stream] provides the binary data, and [size] specifies the
  /// expected total size in bytes. An error will be thrown if the actual
  /// stream size doesn't match the expected size.
  ///
  /// Note: The stream will be consumed when the block is accessed,
  /// and it can only be consumed once unless it's a broadcast stream.
  ///
  /// Example:
  /// ```dart
  /// final streamBlock = Block.fromStream(
  ///   file.openRead(),
  ///   file.lengthSync()
  /// );
  /// ```
  factory Block.fromStream(Stream<Uint8List> stream, int size) = _StreamBlock;

  /// Returns the total size of the block in bytes.
  ///
  /// This represents the total length of all binary data contained in the block.
  ///
  /// Example:
  /// ```dart
  /// final block = Block.fromBytes([Uint8List.fromList([1, 2, 3])]);
  /// print(block.size); // 3
  /// ```
  int get size;

  /// Returns a stream of binary data chunks contained in this block.
  ///
  /// The stream emits the binary data in chunks as [Uint8List] objects.
  /// The sum of all chunk lengths will equal [size].
  ///
  /// Example:
  /// ```dart
  /// final block = Block.fromBytes([
  ///   Uint8List.fromList([1, 2, 3]),
  ///   Uint8List.fromList([4, 5, 6])
  /// ]);
  /// await for (final chunk in block.stream()) {
  ///   print(chunk); // First [1, 2, 3], then [4, 5, 6]
  /// }
  /// ```
  Stream<Uint8List> stream();

  /// Returns a Future that completes with the entire block's content as a single [Uint8List].
  ///
  /// This is useful when you need to process the entire binary data at once.
  /// The result is cached, so subsequent calls are efficient.
  ///
  /// Example:
  /// ```dart
  /// final block = Block.fromBytes([
  ///   Uint8List.fromList([1, 2, 3]),
  ///   Uint8List.fromList([4, 5, 6])
  /// ]);
  /// final allBytes = await block.bytes();
  /// print(allBytes); // [1, 2, 3, 4, 5, 6]
  /// ```
  Future<Uint8List> bytes() {
    return _FutureBlockBytes(this);
  }

  /// Returns a Future that completes with the entire block's content as a UTF-8 decoded string.
  ///
  /// This is useful when the block contains text data.
  /// The result is cached, so subsequent calls are efficient.
  ///
  /// If the data contains invalid UTF-8 sequences, they are handled with a best-effort approach
  /// by allowing malformed input.
  ///
  /// Example:
  /// ```dart
  /// final block = Block.fromString(['Hello', ' ', 'World']);
  /// final text = await block.text();
  /// print(text); // "Hello World"
  /// ```
  Future<String> text() {
    return _FutureBlockText(this);
  }

  /// Creates a new Block that is a slice of this block, from [start] to [end].
  ///
  /// The [start] parameter specifies the offset of the first byte in the new block.
  /// The [end] parameter specifies the offset after the last byte in the new block.
  /// If [end] is not provided, it defaults to the size of the block.
  ///
  /// Both [start] and [end] can be negative, in which case they are interpreted
  /// as offsets from the end of the block (like Python's slice notation).
  ///
  /// Example:
  /// ```dart
  /// final block = Block.fromBytes([Uint8List.fromList([1, 2, 3, 4, 5])]);
  /// final slice = block.slice(1, 4); // Contains bytes [2, 3, 4]
  /// final lastTwo = block.slice(-2);  // Contains bytes [4, 5]
  /// ```
  ///
  /// Throws [ArgumentError] if the resulting slice would be invalid.
  Block slice(int start, [int? end]) {
    if (start < 0) start = size + start;

    end ??= size;
    if (end < 0) end = size + end;

    if (start < 0 || start > size) {
      throw ArgumentError('Invalid start position');
    }
    if (end > size || end < start) {
      throw ArgumentError('Invalid end position');
    }

    return _SliceBlock(this, start, end);
  }
}

class _SliceBlock with Block {
  _SliceBlock(this.parent, this.start, this.end)
    : assert(start >= 0 && start <= end && end <= parent.size),
      size = end - start;

  final Block parent;
  final int start;
  final int end;

  @override
  final int size;

  @override
  Stream<Uint8List> stream() async* {
    int bytesRead = 0;
    int bytesEmitted = 0;
    final targetSize = end - start;

    await for (final chunk in parent.stream()) {
      if (chunk.isEmpty) continue;

      final chunkStart = bytesRead;
      final chunkEnd = chunkStart + chunk.length;

      if (chunkEnd <= start || chunkStart >= end) {
        bytesRead += chunk.length;
        continue;
      }

      final subStart = start > chunkStart ? start - chunkStart : 0;
      final subEnd = end < chunkEnd ? end - chunkStart : chunk.length;

      if (subEnd > subStart) {
        yield chunk.sublist(subStart, subEnd);
        bytesEmitted += (subEnd - subStart);

        if (bytesEmitted >= targetSize) break;
      }

      bytesRead += chunk.length;
    }
  }
}

abstract class _FutureBlockComputation<T> implements Future<T> {
  _FutureBlockComputation(this.block);

  final Block block;

  Future<T> compute();

  // 缓存的计算结果
  late final Future<T> _computation = compute();

  @override
  Stream<T> asStream() => _computation.asStream();

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) =>
      _computation.catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => _computation.then(onValue, onError: onError);

  @override
  Future<T> whenComplete(FutureOr Function() action) =>
      _computation.whenComplete(action);

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _computation.timeout(timeLimit, onTimeout: onTimeout);
}

class _FutureBlockBytes extends _FutureBlockComputation<Uint8List> {
  _FutureBlockBytes(super.block);

  @override
  Future<Uint8List> compute() async {
    final cached = _bytesExpando[block];
    if (cached != null) return cached;

    if (block.size < 10 * 1024 * 1024) {
      final bytes = Uint8List(block.size);
      int start = 0;
      await for (final chunk in block.stream()) {
        bytes.setAll(start, chunk);
        start += chunk.length;
      }
      return _bytesExpando[block] = bytes;
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in block.stream()) {
      builder.add(chunk);
    }

    assert(builder.length == block.size);
    if (builder.length != block.size) {
      throw StateError('Block size mismatch');
    }

    return _bytesExpando[block] = builder.takeBytes();
  }
}

class _FutureBlockText extends _FutureBlockComputation<String> {
  _FutureBlockText(super.block);

  @override
  Future<String> compute() async {
    final cached = _stringExpando[block];
    if (cached != null) return cached;

    final bytes = await block.bytes();
    try {
      return _stringExpando[block] = utf8.decode(bytes);
    } catch (e) {
      if (e is FormatException) {
        final result = utf8.decode(bytes, allowMalformed: true);
        return _stringExpando[block] = result;
      }

      rethrow;
    }
  }
}

class _BlockWithBuilder with Block {
  _BlockWithBuilder(this.builder);

  final Builder builder;

  late final bags = <Uint8List>[];
  late final int lengthInBytes;

  bool initialized = false;

  @override
  int get size {
    ensureInitialized();
    return lengthInBytes;
  }

  @override
  Stream<Uint8List> stream() {
    ensureInitialized();
    return Stream.fromIterable(bags);
  }

  void ensureInitialized() {
    if (initialized) return;
    initialized = true;
    builder(bags.add);
    lengthInBytes = bags.fold(0, (total, bag) => total + bag.lengthInBytes);
  }
}

class _EmptyBlock with Block {
  const _EmptyBlock();

  @override
  int get size => 0;

  @override
  Stream<Uint8List> stream() => Stream.empty();
}

class _StreamBlock with Block {
  _StreamBlock(this.source, this.size);

  final Stream<Uint8List> source;

  @override
  final int size;

  // 缓存流数据
  final _cache = <Uint8List>[];
  bool _isStreamConsumed = false;

  @override
  Stream<Uint8List> stream() async* {
    // 如果已经缓存了数据，直接从缓存返回
    if (_isStreamConsumed) {
      yield* Stream.fromIterable(_cache);
      return;
    }

    // 首次访问时，消费原始流并缓存数据
    int total = 0;
    await for (final chunk in source) {
      _cache.add(chunk);
      total += chunk.lengthInBytes;
      yield chunk;
    }

    _isStreamConsumed = true;

    if (total != size) {
      // 清空缓存，因为数据不匹配
      _cache.clear();
      throw StateError('Stream size mismatch: expected $size, got $total');
    }
  }
}

extension on List<int> {
  Uint8List toBytes() {
    return switch (this) {
      Uint8List value => value,
      TypedData(:final buffer) => buffer.asUint8List(),
      _ => Uint8List.fromList(this),
    };
  }
}
