/// Decompression-bomb guard for PDFs: DEFENCE IN DEPTH. The hard protection
/// is the output cap inside the vendored decoders (third_party/pdf_cos,
/// `// dhruva: bounded decode`), which holds whatever this guard guesses
/// about stream boundaries. Upstream pdf_cos decodes with no cap, so a tiny
/// crafted file could expand to gigabytes and kill the app. Before the
/// parser sees the bytes this guard (which fails closed) also:
///
/// 1. parses every stream dictionary (any `<<...>>` followed by `stream`,
///    wherever it sits in the file, because the parser also accepts streams
///    nested in other dictionaries and inside raw object streams) and ALLOWS
///    only no filter, one FlateDecode, or an image-only filter on an image;
///    filter chains (ASCII85/ASCIIHex/RunLength/LZW + Flate), indirect or
///    malformed /Filter and /DecodeParms are refused, so nothing the guard
///    cannot bound ever reaches a decoder;
/// 2. inflates each allowed Flate stream here in small chunks and aborts as
///    soon as a per-stream or total limit is hit, and refuses inflated data
///    that itself contains a stream (an object stream smuggling a filter
///    chain past step 1).
///
/// 3. refuses encrypted files (any dictionary with an /Encrypt entry: the
///    trailer, or a cross-reference stream's dictionary). Stream payloads of
///    an encrypted file are ciphertext, so steps 1-2 would inflate noise and
///    wave through a stream that only becomes a bomb once decrypted (and
///    `PdfDocument.open` auto-authenticates the empty password).
///
/// Text extraction never decodes image streams (`resolveOverprint: false`
/// and `collectImages: false` keep `drawImage` a no-op), and the parser
/// decodes DCT/JPX/JBIG2 never (it throws), so those are safe to leave alone.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getAdler32;

/// Largest inflated size accepted for one stream.
const maxInflatedStreamBytes = 64 * 1024 * 1024;

/// Largest inflated size accepted for all streams of one file together.
const maxInflatedTotalBytes = 200 * 1024 * 1024;

const _inputChunk = 64 * 1024;
const _incomplete = -1;
const _garbage = -2;

/// The file must be refused (limit hit, or a stream the guard cannot bound).
final class _LimitExceeded implements Exception {
  const _LimitExceeded();
}

/// An /Encrypt entry was found: the file must be refused as encrypted.
final class _Encrypted implements Exception {
  const _Encrypted();
}

/// Syntax the PDF parser would reject too, so no stream can come of it.
final class _Malformed implements Exception {
  const _Malformed();
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

/// What the guard decided about a file.
enum PdfGuardVerdict { safe, encrypted, unsafe }

/// True when [bytes] are safe to hand to the PDF parser (see the library
/// comment). Garbage that is not zlib data is ignored here; the parser copes
/// with that itself. Limits are parameters so tests can use small ones.
bool pdfSafeToParse(
  Uint8List bytes, {
  int maxStream = maxInflatedStreamBytes,
  int maxTotal = maxInflatedTotalBytes,
}) =>
    pdfGuard(bytes, maxStream: maxStream, maxTotal: maxTotal) ==
    PdfGuardVerdict.safe;

/// [pdfSafeToParse] with the reason for a refusal: [PdfGuardVerdict.encrypted]
/// for a file with an /Encrypt entry, [PdfGuardVerdict.unsafe] for anything
/// else the guard cannot bound.
PdfGuardVerdict pdfGuard(
  Uint8List bytes, {
  int maxStream = maxInflatedStreamBytes,
  int maxTotal = maxInflatedTotalBytes,
}) {
  final List<_FlateStart> flateStarts;
  try {
    flateStarts = _flateStreamStarts(bytes, maxStream);
  } on _Encrypted {
    return PdfGuardVerdict.encrypted;
  } on _LimitExceeded {
    return PdfGuardVerdict.unsafe;
  }
  var total = 0;
  // Bounds the work when an attacker packs many stream starts into the file.
  var feedBudget = bytes.length * 4 + (1 << 20);

  // Inflates bytes[start, end). Returns the inflated size, _incomplete when
  // the zlib data was cut off, or _garbage when it is not zlib. Throws
  // _LimitExceeded past a limit. dart:io's inflater reports a cut-off stream
  // as success, so completeness is checked by finding the Adler-32 of
  // everything inflated just before the end of the segment.
  int inflate(int start, int end) {
    var n = 0;
    var adler = 1;
    final nested = _NestedStreamDetector();
    final sink = ZLibDecoder().startChunkedConversion(
      _ChunkSink((out) {
        if (n == 0 && _looksLikeZlib(out)) throw const _LimitExceeded();
        if (nested.feed(out)) throw const _LimitExceeded();
        n += out.length;
        adler = getAdler32(out, adler);
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
      return _adlerNearEnd(bytes, start, end, adler) ? n : _incomplete;
    } on _LimitExceeded {
      rethrow;
    } on Object {
      return _incomplete;
    }
  }

  for (final s in flateStarts) {
    try {
      // Segment like the parser: a direct /Length is trusted when
      // `endstream` follows it, else the next `endstream` marker ends the
      // data. The marker may sit inside the deflate data itself, so an
      // incomplete result retries with the segment extended (a few times).
      // A stream still incomplete after that is REFUSED: the guard cannot
      // say where the parser ends it (the decoder's own cap would still
      // hold, but this is defence in depth, so it fails closed).
      final len = s.length;
      var end = len != null && _endstreamFollows(bytes, s.data + len)
          ? s.data + len
          : _indexOfEndstream(bytes, s.data);
      var n = _incomplete;
      for (var tries = 0; tries < 8; tries++) {
        n = inflate(s.data, end);
        if (n >= 0) total += n;
        if (n != _incomplete || end >= bytes.length) break;
        end = _indexOfEndstream(bytes, end + 9);
      }
      if (n == _incomplete) return PdfGuardVerdict.unsafe;
    } on _LimitExceeded {
      return PdfGuardVerdict.unsafe;
    }
  }
  return PdfGuardVerdict.safe;
}

/// True when the big-endian [adler] sits in the last bytes of bytes[start, end)
/// (zlib's trailer, maybe followed by a little padding).
bool _adlerNearEnd(Uint8List b, int start, int end, int adler) {
  final from = end - 64 > start ? end - 64 : start;
  for (var i = from; i + 4 <= end; i++) {
    if ((b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3]) == adler) {
      return true;
    }
  }
  return false;
}

/// The parser's `_endstreamFollows`: optional whitespace, then `endstream`.
bool _endstreamFollows(Uint8List b, int at) {
  if (at < 0 || at > b.length) return false;
  var p = at;
  while (p < b.length && _isWs(b[p])) {
    p++;
  }
  const kw = [0x65, 0x6e, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];
  if (p + kw.length > b.length) return false;
  for (var k = 0; k < kw.length; k++) {
    if (b[p + k] != kw[k]) return false;
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

// ---------------------------------------------------------------------------
// Stream-dictionary scan. A small mirror of the parser's own grammar (the
// parser's lexer is not reachable without a new dependency). Wherever it is
// unsure it refuses; where the parser itself would throw it gives up on that
// candidate, since no stream can come of it.
// ---------------------------------------------------------------------------

const _flateNames = {'FlateDecode', 'Fl'};
const _imageNames = {'DCTDecode', 'JPXDecode', 'JBIG2Decode'};
const _ccittName = 'CCITTFaxDecode';
const _maxDictDepth = 64;
const _maxParamDim = 1 << 20;
const _maxPredictorRow = 8 * 1024 * 1024;

final class _Name {
  const _Name(this.value);
  final String value;
}

/// An indirect reference or any scalar the guard does not interpret.
final class _Opaque {
  const _Opaque();
}

const _opaque = _Opaque();

enum _T {
  dictOpen,
  dictClose,
  arrOpen,
  arrClose,
  name,
  integer,
  other,
  word,
  eof,
}

final class _Tok {
  const _Tok(this.type, this.end, [this.value]);
  final _T type;
  final int end;
  final Object? value;
  bool isWord(String w) => type == _T.word && value == w;
}

bool _isWs(int c) =>
    c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;
bool _isDelim(int c) =>
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3c ||
    c == 0x3e ||
    c == 0x5b ||
    c == 0x5d ||
    c == 0x7b ||
    c == 0x7d ||
    c == 0x2f ||
    c == 0x25;
bool _isRegular(int c) => !_isWs(c) && !_isDelim(c);
int _hex(int c) => c >= 0x30 && c <= 0x39
    ? c - 0x30
    : c >= 0x41 && c <= 0x46
    ? c - 0x37
    : c >= 0x61 && c <= 0x66
    ? c - 0x57
    : -1;

final class _Lexer {
  _Lexer(this.b, this.p);
  final Uint8List b;
  int p;
  final _ahead = <_Tok>[];

  _Tok peek([int n = 0]) {
    while (_ahead.length <= n) {
      _ahead.add(_lex());
    }
    return _ahead[n];
  }

  _Tok next() => _ahead.isNotEmpty ? _ahead.removeAt(0) : _lex();

  _Tok _lex() {
    while (p < b.length) {
      if (_isWs(b[p])) {
        p++;
      } else if (b[p] == 0x25) {
        while (p < b.length && b[p] != 10 && b[p] != 13) {
          p++;
        }
      } else {
        break;
      }
    }
    if (p >= b.length) return _Tok(_T.eof, p);
    final c = b[p];
    switch (c) {
      case 0x5b:
        return _Tok(_T.arrOpen, ++p);
      case 0x5d:
        return _Tok(_T.arrClose, ++p);
      case 0x3c:
        if (p + 1 < b.length && b[p + 1] == 0x3c) {
          p += 2;
          return _Tok(_T.dictOpen, p);
        }
        p++;
        while (true) {
          if (p >= b.length) throw const _Malformed();
          final h = b[p++];
          if (h == 0x3e) return _Tok(_T.other, p);
          if (!_isWs(h) && _hex(h) < 0) throw const _Malformed();
        }
      case 0x3e:
        if (p + 1 < b.length && b[p + 1] == 0x3e) {
          p += 2;
          return _Tok(_T.dictClose, p);
        }
        throw const _Malformed();
      case 0x29:
        throw const _Malformed();
      case 0x28:
        var depth = 1;
        p++;
        while (depth > 0) {
          if (p >= b.length) throw const _Malformed();
          final s = b[p++];
          if (s == 0x5c) {
            p++;
          } else if (s == 0x28) {
            depth++;
          } else if (s == 0x29) {
            depth--;
          }
        }
        return _Tok(_T.other, p);
      case 0x2f:
        return _name();
      case 0x7b || 0x7d:
        p++;
        return _Tok(_T.word, p, c == 0x7b ? '{' : '}');
    }
    if (c == 0x2b || c == 0x2d || c == 0x2e || (c >= 0x30 && c <= 0x39)) {
      final start = p;
      while (p < b.length) {
        final d = b[p];
        if ((d >= 0x30 && d <= 0x39) || d == 0x2e || d == 0x2b || d == 0x2d) {
          p++;
        } else {
          break;
        }
      }
      // A real, or a malformed number, is not an int: opaque, never trusted.
      final v = int.tryParse(String.fromCharCodes(b, start, p));
      return v == null ? _Tok(_T.other, p) : _Tok(_T.integer, p, v);
    }
    final start = p;
    while (p < b.length && _isRegular(b[p])) {
      p++;
    }
    return _Tok(_T.word, p, String.fromCharCodes(b, start, p));
  }

  _Tok _name() {
    p++;
    final out = <int>[];
    while (p < b.length && _isRegular(b[p])) {
      var c = b[p++];
      if (c == 0x23 && p + 1 < b.length) {
        final h1 = _hex(b[p]);
        final h2 = _hex(b[p + 1]);
        if (h1 >= 0 && h2 >= 0) {
          c = (h1 << 4) | h2;
          p += 2;
        }
      }
      out.add(c);
    }
    return _Tok(_T.name, p, String.fromCharCodes(out));
  }

  /// One object, as the parser reads it: [_Name], [int], `Map`, `List`,
  /// `null` for the null object, else [_opaque].
  Object? value(int depth) {
    if (depth > _maxDictDepth) throw const _LimitExceeded();
    final t = peek();
    switch (t.type) {
      case _T.integer:
        if (peek(1).type == _T.integer && peek(2).isWord('R')) {
          next();
          next();
          next();
          return _opaque;
        }
        next();
        return t.value;
      case _T.other:
        next();
        return _opaque;
      case _T.name:
        next();
        return _Name(t.value! as String);
      case _T.arrOpen:
        next();
        final items = <Object?>[];
        while (peek().type != _T.arrClose) {
          if (peek().type == _T.eof) throw const _Malformed();
          items.add(value(depth + 1));
        }
        next();
        return items;
      case _T.dictOpen:
        return dict(depth);
      case _T.word:
        next();
        return switch (t.value) {
          'true' || 'false' => _opaque,
          'null' => null,
          _ => throw const _Malformed(),
        };
      case _T.eof || _T.arrClose || _T.dictClose:
        throw const _Malformed();
    }
  }

  Map<String, Object?> dict(int depth) {
    next(); // <<
    final d = <String, Object?>{};
    while (peek().type != _T.dictClose) {
      final k = peek();
      if (k.type != _T.name) throw const _Malformed();
      next();
      d[k.value! as String] = value(depth + 1);
    }
    next();
    return d;
  }
}

/// Where a Flate stream's data begins, and its direct integer /Length (null
/// when absent or indirect), which the parser trusts when `endstream` follows.
final class _FlateStart {
  const _FlateStart(this.data, this.length);
  final int data;
  final int? length;
}

/// Every FlateDecode stream the guard must inflate. Throws [_LimitExceeded]
/// on the first stream that is not on the allow-list, and [_Encrypted] on the
/// first dictionary with an /Encrypt entry.
List<_FlateStart> _flateStreamStarts(Uint8List bytes, int maxStream) {
  final starts = <_FlateStart>[];
  // Every `<<` is a candidate, so nested dictionaries, dictionaries inside
  // raw object streams and overlapping decoys are all seen. The budget keeps
  // a file built from unclosed dictionaries or strings from going quadratic.
  var budget = bytes.length * 4 + (1 << 20);
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] != 0x3c || bytes[i + 1] != 0x3c) continue;
    final lx = _Lexer(bytes, i);
    int? data;
    int? length;
    try {
      final d = lx.dict(0);
      if (d['Encrypt'] != null) throw const _Encrypted();
      final t = lx.peek();
      if (t.isWord('stream')) {
        data = t.end;
        if (data < bytes.length && bytes[data] == 0x0d) {
          data++;
          if (data < bytes.length && bytes[data] == 0x0a) data++;
        } else if (data < bytes.length && bytes[data] == 0x0a) {
          data++;
        }
        if (!_classify(d, maxStream)) data = null;
        final len = d['Length'];
        if (len is int && len >= 0) length = len;
      }
    } on _Malformed {
      // the parser would reject this too
    }
    // Overlapping decoys can give one data start two /Length readings: keep
    // every (start, length) pair.
    if (data != null) starts.add(_FlateStart(data, length));
    budget -= lx.p - i;
    if (budget < 0) throw const _LimitExceeded();
  }
  return starts;
}

/// True for a stream to inflate-check, false for one needing no decoding;
/// throws [_LimitExceeded] for anything else. The parser reads only /Filter
/// and /DecodeParms (/DP); it follows indirect objects in them, which the
/// guard cannot do cheaply, so those are refused. A direct /Length steers the
/// segmentation in [pdfSafeToParse]; an indirect one is not followed.
bool _classify(Map<String, Object?> d, int maxStream) {
  const refuse = _LimitExceeded();
  final f = d['Filter'];
  final names = <String>[];
  if (f is _Name) {
    names.add(f.value);
  } else if (f is List<Object?>) {
    for (final item in f) {
      if (item is! _Name) throw refuse;
      names.add(item.value);
    }
  } else if (f != null) {
    throw refuse;
  }

  // Every /DecodeParms entry must be a direct dictionary (or null).
  final params = <Map<String, Object?>>[];
  Map<String, Object?>? first;
  for (final key in const ['DecodeParms', 'DP']) {
    final v = d[key];
    final entries = v is List<Object?> ? v : [v];
    for (var k = 0; k < entries.length; k++) {
      final e = entries[k];
      if (e == null) continue;
      if (e is! Map<String, Object?>) throw refuse;
      params.add(e);
      if (key == 'DecodeParms' && k == 0) first = e;
    }
  }

  if (names.isEmpty) return false;
  if (names.length != 1) throw refuse;
  final name = names.single;
  final subtype = d['Subtype'];
  final isImage = subtype is _Name && subtype.value == 'Image';

  if (_flateNames.contains(name)) {
    if (!params.every(_predictorBounded)) throw refuse;
    return true;
  }
  if (isImage && _imageNames.contains(name)) return false;
  // CCITT is decoded generically by the parser with geometry taken from
  // /DecodeParms, so it needs an explicit, bounded Rows x Columns.
  if (isImage && name == _ccittName) {
    final columns = first?['Columns'] ?? 1728;
    final rows = first?['Rows'] ?? 0;
    if (columns is int &&
        rows is int &&
        columns > 0 &&
        columns <= _maxParamDim &&
        rows > 0 &&
        rows <= _maxParamDim * 64 &&
        rows * ((columns + 7) >> 3) <= maxStream) {
      return false;
    }
  }
  throw refuse;
}

/// The PNG/TIFF predictor allocates a row buffer from /Columns etc.
bool _predictorBounded(Map<String, Object?> p) {
  int n(String k, int fallback) {
    final v = p[k];
    return v is int ? v : fallback;
  }

  if (n('Predictor', 1) <= 1) return true;
  final colors = n('Colors', 1);
  final bits = n('BitsPerComponent', 8);
  final columns = n('Columns', 1);
  if (colors < 1 || bits < 1 || columns < 1) return false;
  if (colors > _maxParamDim || bits > _maxParamDim || columns > _maxParamDim) {
    return false;
  }
  return (colors * bits * columns + 7) ~/ 8 <= _maxPredictorRow;
}

/// Finds `>>` then `stream` (whitespace and comments allowed between, as the
/// parser does) in inflated data: a stream hiding inside an object stream.
final class _NestedStreamDetector {
  // 0 idle, 1 after '>', 2 after '>>', 3 in comment, 4.. matching "stream".
  var _s = 0;
  static const _kw = [0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];

  bool feed(List<int> chunk) {
    var s = _s;
    for (var i = 0; i < chunk.length; i++) {
      final c = chunk[i];
      if (s >= 4) {
        if (c == _kw[s - 3]) {
          if (++s == 4 + _kw.length - 1) return true;
          continue;
        }
        s = 0;
      }
      switch (s) {
        case 0:
          if (c == 0x3e) s = 1;
        case 1:
          s = c == 0x3e ? 2 : 0;
        case 2:
          if (c == 0x25) {
            s = 3;
          } else if (c == _kw[0]) {
            s = 4;
          } else if (c == 0x3e) {
            s = 1;
          } else if (!_isWs(c)) {
            s = 0;
          }
        case 3:
          if (c == 10 || c == 13) s = 2;
      }
    }
    _s = s;
    return false;
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
