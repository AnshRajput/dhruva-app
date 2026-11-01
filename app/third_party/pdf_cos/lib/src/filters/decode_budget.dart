// dhruva: bounded decode (this whole file is new; not part of upstream).
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
