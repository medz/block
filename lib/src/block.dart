import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

final _bytesExpando = Expando<Uint8List>('block://cache/bytes');
final _stringExpando = Expando<String>('block://cache/string');

typedef Updates = void Function(Uint8List bag);
typedef Builder = void Function(Updates updates);

abstract mixin class Block {
  factory Block(Builder builder) = _BlockWithBuilder;
  factory Block.empty() => const _EmptyBlock();
  factory Block.fromString(Iterable<String> bags, {Encoding encoding = utf8}) {
    return Block((updates) {
      for (final bag in bags) {
        updates(encoding.encode(bag).toBytes());
      }
    });
  }
  factory Block.fromBytes(Iterable<Uint8List> bags) {
    return Block((updates) {
      for (final bytes in bags) {
        updates(bytes);
      }
    });
  }
  factory Block.formStream(Stream<Uint8List> stream, int size) = _StreamBlock;

  int get size;

  Stream<Uint8List> stream();

  Future<Uint8List> bytes() {
    return _FutureBlockBytes(this);
  }

  Future<String> text() {
    return _FutureBlockText(this);
  }

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
  const _StreamBlock(this.source, this.size);

  final Stream<Uint8List> source;

  @override
  final int size;

  @override
  Stream<Uint8List> stream() async* {
    int total = 0;
    await for (final chunk in source) {
      total += chunk.lengthInBytes;
      yield chunk;
    }

    if (total != size) {
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
