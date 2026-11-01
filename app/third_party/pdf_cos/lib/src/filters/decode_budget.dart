// dhruva: bounded decode (this whole file is new; not part of upstream).
import 'dart:typed_data';

import '../exceptions.dart';

/// Hard output caps for stream decoding, enforced INSIDE every filter so the
/// result never depends on how a caller guessed where a stream ends.
///
/// One budget belongs to one document ([CosDocument.decodeBudget]); every
/// filter stage of every stream decoded for that document draws from it.
/// Output is charged as it is produced (before big allocations), and the
/// first breach throws [PdfDecodeLimitExceeded] and latches [tripped], so a
/// caller that swallows the exception can still see that the cap was hit.
class DecodeBudget {
  DecodeBudget({
    this.maxStreamBytes = defaultMaxStreamBytes,
    this.maxTotalBytes = defaultMaxTotalBytes,
  });

  /// Largest output of one filter stage.
  static const defaultMaxStreamBytes = 16 * 1024 * 1024;

  /// Largest output of all filter stages of one document together.
  static const defaultMaxTotalBytes = 128 * 1024 * 1024;

  final int maxStreamBytes;
  final int maxTotalBytes;

  int _used = 0;
  bool _tripped = false;

  /// Bytes charged so far across the document.
  int get usedBytes => _used;

  /// True once any stage has crossed a cap.
  bool get tripped => _tripped;

  /// Starts accounting for one filter stage's output.
  DecodeStage stage() => DecodeStage._(this);

  Never _trip(String detail) {
    _tripped = true;
    throw PdfDecodeLimitExceeded(detail);
  }
}

/// Output accounting for one filter stage; see [DecodeBudget.stage].
class DecodeStage {
  DecodeStage._(this._budget);

  final DecodeBudget _budget;
  int _n = 0;

  /// Most bytes this stage may still produce.
  int get remaining {
    final left = _budget.maxTotalBytes - _budget._used;
    final stage = _budget.maxStreamBytes - _n;
    final r = left < stage ? left : stage;
    return r < 0 ? 0 : r;
  }

  /// Latches the budget as tripped and throws.
  Never trip(String detail) => _budget._trip(detail);

  /// Charges [bytes] of output (call BEFORE allocating them).
  void add(int bytes) {
    if (bytes < 0 || bytes > _budget.maxTotalBytes) {
      _budget._trip('stream output past the document limit');
    }
    _n += bytes;
    _budget._used += bytes;
    if (_n > _budget.maxStreamBytes) {
      _budget._trip('stream output past ${_budget.maxStreamBytes} bytes');
    }
    if (_budget._used > _budget.maxTotalBytes) {
      _budget._trip('document output past ${_budget.maxTotalBytes} bytes');
    }
  }
}

/// Test hook: counts every backing buffer [DecodeBuffer] allocates, so a
/// memory regression test can assert "one growing buffer, not one object per
/// run/code" deterministically instead of sampling RSS.
class DecodeBufferStats {
  DecodeBufferStats._();

  /// Backing buffers allocated since [reset] (the doubling steps of every
  /// [DecodeBuffer]; a well-behaved filter makes O(log n) of them).
  static int allocations = 0;

  /// Sum of the capacities of those buffers.
  static int allocatedBytes = 0;

  /// Largest number of bytes live at once inside one [DecodeBuffer]: old plus
  /// new backing array while it grows, and the trimmed copy in
  /// [DecodeBuffer.takeBytes].
  static int peakLiveBytes = 0;

  static void reset() {
    allocations = 0;
    allocatedBytes = 0;
    peakLiveBytes = 0;
  }

  static void _alloc(int capacity, int alsoLive) {
    allocations++;
    allocatedBytes += capacity;
    final live = capacity + alsoLive;
    if (live > peakLiveBytes) peakLiveBytes = live;
  }
}

/// The one output buffer of a filter stage: a single [Uint8List] that doubles
/// up to the stage's remaining budget and never holds one object per run,
/// code or row. Callers charge the [DecodeStage] BEFORE writing; the limit
/// here is only a backstop, and crossing it trips the budget.
class DecodeBuffer {
  DecodeBuffer(this._stage, {int expected = 0})
    : limit = _stage.remaining,
      _buf = Uint8List(_initial(_stage.remaining, expected)) {
    DecodeBufferStats._alloc(_buf.length, 0);
  }

  static int _initial(int limit, int expected) {
    var n = expected < 4096 ? 4096 : expected;
    if (n > limit) n = limit;
    return n;
  }

  final DecodeStage _stage;

  /// Most bytes this buffer may hold.
  final int limit;
  Uint8List _buf;
  int _n = 0;

  int get length => _n;

  void _ensure(int extra) {
    final need = _n + extra;
    if (need > limit) _stage.trip('decode buffer past $limit bytes');
    if (need <= _buf.length) return;
    var cap = _buf.length < 4096 ? 4096 : _buf.length;
    while (cap < need) {
      cap *= 2;
    }
    if (cap > limit) cap = limit;
    final next = Uint8List(cap)..setRange(0, _n, _buf);
    DecodeBufferStats._alloc(cap, _buf.length);
    _buf = next;
  }

  void addByte(int b) {
    if (_n == _buf.length) _ensure(1);
    _buf[_n++] = b;
  }

  /// Appends data[start, end).
  void addRange(Uint8List data, int start, int end) {
    final count = end - start;
    _ensure(count);
    _buf.setRange(_n, _n + count, data, start);
    _n += count;
  }

  /// Appends [count] copies of [byte].
  void fill(int byte, int count) {
    _ensure(count);
    _buf.fillRange(_n, _n + count, byte);
    _n += count;
  }

  /// Reserves [count] bytes and returns the offset of the first; the caller
  /// writes them through [bytes].
  int reserve(int count) {
    _ensure(count);
    final at = _n;
    _n += count;
    return at;
  }

  /// The backing array (valid until the next write).
  Uint8List get bytes => _buf;

  /// The result: the backing array itself when exactly full, else a trimmed
  /// copy so the slack is not retained.
  Uint8List takeBytes() {
    if (_n == _buf.length) return _buf;
    DecodeBufferStats._alloc(_n, _buf.length);
    return Uint8List.sublistView(_buf, 0, _n).sublist(0);
  }
}
