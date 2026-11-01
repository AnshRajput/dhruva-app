/// Decompression-bomb guard for PDFs. The PDF parser inflates FlateDecode
/// streams with no output cap, so a tiny crafted file can expand to gigabytes
/// and take the whole app down (an isolate OOM kills the process). Before the
/// parser sees the bytes, every candidate stream is inflated here in small
/// chunks and the scan aborts as soon as a per-stream or total limit is hit.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Largest inflated size accepted for one stream.
const maxInflatedStreamBytes = 64 * 1024 * 1024;

/// Largest inflated size accepted for all streams of one file together.
const maxInflatedTotalBytes = 200 * 1024 * 1024;

const _inputChunk = 64 * 1024;
const _incomplete = -1;
const _garbage = -2;

final class _LimitExceeded implements Exception {
  const _LimitExceeded();
}

/// Forwards every decoded chunk as it is produced. (`ByteConversionSink.
/// withCallback` would buffer the whole output until close, which is exactly
/// the memory blow-up this guard exists to prevent.)
final class _ChunkSink extends ByteConversionSinkBase {
  final void Function(List<int> chunk) _onChunk;
  _ChunkSink(this._onChunk);

  @override
  void add(List<int> chunk) => _onChunk(chunk);

  @override
  void close() {}
}

/// True when [bytes] are safe to hand to the PDF parser: no FlateDecode
/// stream (or nested Flate-in-Flate stream) inflates past the limits. Garbage
/// that is not zlib data is ignored here; the parser copes with that itself.
/// Limits are parameters so tests can use small ones.
bool pdfInflateWithinLimits(
  Uint8List bytes, {
  int maxStream = maxInflatedStreamBytes,
  int maxTotal = maxInflatedTotalBytes,
}) {
  var total = 0;
  // Bounds the work when an attacker packs many stream starts into the file.
  var feedBudget = bytes.length * 4 + (1 << 20);

  // Inflates bytes[start, end). Returns the inflated size, _incomplete when
  // the zlib data was cut off, or _garbage when it is not zlib. Throws
  // _LimitExceeded past a limit.
  int inflate(int start, int end) {
    var n = 0;
    final sink = ZLibDecoder().startChunkedConversion(
      _ChunkSink((out) {
        if (n == 0 && _looksLikeZlib(out)) throw const _LimitExceeded();
        n += out.length;
        if (n > maxStream || total + n > maxTotal) {
          throw const _LimitExceeded();
        }
      }),
    );
    try {
      for (var p = start; p < end; p += _inputChunk) {
        final next = p + _inputChunk < end ? p + _inputChunk : end;
        feedBudget -= next - p;
        if (feedBudget < 0) throw const _LimitExceeded();
        sink.add(Uint8List.sublistView(bytes, p, next));
      }
    } on _LimitExceeded {
      rethrow;
    } on Object {
      return _garbage;
    }
    try {
      sink.close();
      return n;
    } on _LimitExceeded {
      rethrow;
    } on Object {
      return _incomplete;
    }
  }

  for (final start in _streamStarts(bytes)) {
    try {
      // The next `endstream` may sit inside the deflate data itself, so an
      // incomplete result retries with the segment extended (a few times).
      var end = _indexOfEndstream(bytes, start);
      for (var tries = 0; tries < 8; tries++) {
        final n = inflate(start, end);
        if (n >= 0) total += n;
        if (n != _incomplete || end >= bytes.length) break;
        end = _indexOfEndstream(bytes, end + 9);
      }
    } on _LimitExceeded {
      return false;
    }
  }
  return true;
}

/// zlib header: 0x78 plus one of the four standard FLG bytes. A decoded
/// content stream that starts this way is a second compression layer, which
/// this guard does not follow, so it is refused outright.
bool _looksLikeZlib(List<int> out) =>
    out.length >= 2 &&
    out[0] == 0x78 &&
    (out[1] == 0x01 || out[1] == 0x5e || out[1] == 0x9c || out[1] == 0xda);

// Offsets just past each `stream` keyword's end-of-line.
Iterable<int> _streamStarts(Uint8List b) sync* {
  const kw = [0x73, 0x74, 0x72, 0x65, 0x61, 0x6d]; // "stream"
  final last = b.length - kw.length - 1;
  for (var i = 0; i < last; i++) {
    if (b[i] != 0x73) continue;
    var match = true;
    for (var k = 1; k < kw.length; k++) {
      if (b[i + k] != kw[k]) {
        match = false;
        break;
      }
    }
    if (!match) continue;
    // Skip `endstream`.
    if (i >= 3 && b[i - 1] == 0x64 && b[i - 2] == 0x6e && b[i - 3] == 0x65) {
      continue;
    }
    var p = i + kw.length;
    if (b[p] == 0x0d) {
      p++;
      if (p < b.length && b[p] == 0x0a) p++;
    } else if (b[p] == 0x0a) {
      p++;
    } else {
      continue;
    }
    yield p;
  }
}

// Offset of the next `endstream` at or after [from], or the file length.
int _indexOfEndstream(Uint8List b, int from) {
  const kw = [0x65, 0x6e, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];
  final last = b.length - kw.length;
  for (var i = from; i <= last; i++) {
    if (b[i] != 0x65) continue;
    var match = true;
    for (var k = 1; k < kw.length; k++) {
      if (b[i + k] != kw[k]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return b.length;
}
