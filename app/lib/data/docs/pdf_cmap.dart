/// A bounded parser for `/ToUnicode` CMaps (`bfchar`, `bfrange`,
/// `codespacerange`) and the shared entry budget that also limits `/W`
/// width tables.
///
/// Every number read from the file is clamped before it sizes anything: one
/// `bfrange` expands to at most [maxRangeExpansion] entries, and all CMaps
/// and width tables of one document share [maxTableEntries]. A hex string
/// keeps at most 64 bytes however long it is written. The parser never
/// allocates from a count in the data, only from entries it has accepted.
library;

import 'dart:typed_data';

/// Most entries one `bfrange` (or one `/W` range) may expand to.
const maxRangeExpansion = 65536;

/// Most entries all CMaps and width tables of one document may hold.
const maxTableEntries = 1000000;

/// Counts accepted table entries across one document.
final class PdfTableBudget {
  int used = 0;

  /// Takes up to [n] entries and returns how many were granted.
  int take(int n) {
    final left = maxTableEntries - used;
    final granted = n < left ? n : left;
    used += granted < 0 ? 0 : granted;
    return granted < 0 ? 0 : granted;
  }

  bool get exhausted => used >= maxTableEntries;
}

/// Code (1-4 bytes) to Unicode text.
final class ToUnicodeMap {
  // key = (byteLength << 32) | code
  final Map<int, int> _one = {}; // a single code point
  final Map<int, String> _many = {}; // ligatures and other sequences

  /// Codespace ranges as (byteLength, lo, hi), at most 64.
  final List<(int, int, int)> codespace = [];

  /// True when parsing stopped early because the budget ran out.
  bool truncated = false;

  int get entryCount => _one.length + _many.length;

  static int _key(int len, int code) => (len << 32) | code;

  void _put(int len, int code, int cp) {
    final k = _key(len, code);
    _many.remove(k);
    _one[k] = cp;
  }

  void _putText(int len, int code, String text) {
    if (text.isEmpty) return;
    final k = _key(len, code);
    if (text.runes.length == 1) {
      _put(len, code, text.runes.first);
      return;
    }
    _one.remove(k);
    _many[k] = text;
  }

  /// The text for [code] written in [len] bytes, or null.
  String? lookup(int code, int len) {
    final k = _key(len, code);
    final cp = _one[k];
    if (cp != null) return String.fromCharCode(cp);
    return _many[k];
  }

  /// Splits the string at [pos] into the next code: returns its byte length
  /// by matching the codespace ranges (1 byte when none matches).
  int codeLength(Uint8List s, int pos) {
    if (codespace.isEmpty) return 2 <= s.length - pos ? 2 : 1;
    for (var len = 1; len <= 4 && pos + len <= s.length; len++) {
      for (final (l, lo, hi) in codespace) {
        if (l != len) continue;
        var ok = true;
        for (var i = 0; i < len; i++) {
          final shift = 8 * (len - 1 - i);
          final b = s[pos + i];
          if (b < ((lo >> shift) & 0xFF) || b > ((hi >> shift) & 0xFF)) {
            ok = false;
            break;
          }
        }
        if (ok) return len;
      }
    }
    return 1;
  }

  /// Parses [data] (a decoded CMap stream, already capped by the decoder).
  static ToUnicodeMap parse(Uint8List data, PdfTableBudget budget) {
    final map = ToUnicodeMap();
    _Scanner(data, map, budget).run();
    return map;
  }
}

enum _Tok { eof, hex, keyword, arrayOpen, arrayClose, other }

final class _Scanner {
  _Scanner(this.b, this.map, this.budget);

  final Uint8List b;
  final ToUnicodeMap map;
  final PdfTableBudget budget;
  int p = 0;

  // The last hex token: at most 64 bytes kept, `hexLen` clamped to that.
  final Uint8List hex = Uint8List(64);
  int hexLen = 0;
  String word = '';

  static bool _ws(int c) =>
      c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;

  static bool _delim(int c) =>
      c == 0x28 ||
      c == 0x29 ||
      c == 0x3C ||
      c == 0x3E ||
      c == 0x5B ||
      c == 0x5D ||
      c == 0x7B ||
      c == 0x7D ||
      c == 0x2F ||
      c == 0x25;

  static int _nibble(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x37;
    if (c >= 0x61 && c <= 0x66) return c - 0x57;
    return -1;
  }

  _Tok next() {
    while (p < b.length) {
      final c = b[p];
      if (_ws(c)) {
        p++;
      } else if (c == 0x25) {
        while (p < b.length && b[p] != 10 && b[p] != 13) {
          p++;
        }
      } else {
        break;
      }
    }
    if (p >= b.length) return _Tok.eof;
    final c = b[p];
    if (c == 0x3C && !(p + 1 < b.length && b[p + 1] == 0x3C)) {
      p++;
      hexLen = 0;
      var hi = -1;
      var kept = 0;
      while (p < b.length && b[p] != 0x3E) {
        final n = _nibble(b[p++]);
        if (n < 0) continue;
        if (hi < 0) {
          hi = n;
        } else {
          if (kept < hex.length) hex[kept++] = (hi << 4) | n;
          hi = -1;
        }
      }
      if (hi >= 0 && kept < hex.length) hex[kept++] = hi << 4;
      if (p < b.length) p++; // '>'
      hexLen = kept;
      return _Tok.hex;
    }
    if (c == 0x5B) {
      p++;
      return _Tok.arrayOpen;
    }
    if (c == 0x5D) {
      p++;
      return _Tok.arrayClose;
    }
    if (c == 0x28) {
      // a string: skip it, balancing parentheses.
      var depth = 0;
      while (p < b.length) {
        final d = b[p++];
        if (d == 0x5C) {
          p++;
        } else if (d == 0x28) {
          depth++;
        } else if (d == 0x29 && --depth == 0) {
          break;
        }
      }
      return _Tok.other;
    }
    if (_delim(c)) {
      // << >> { } /name : step over the delimiter and its name.
      p++;
      if (c == 0x2F) {
        while (p < b.length && !_ws(b[p]) && !_delim(b[p])) {
          p++;
        }
      }
      return _Tok.other;
    }
    final start = p;
    while (p < b.length && !_ws(b[p]) && !_delim(b[p])) {
      p++;
    }
    final len = p - start;
    word = len > 24 ? '' : String.fromCharCodes(b, start, p);
    return _Tok.keyword;
  }

  int get hexInt {
    var v = 0;
    final n = hexLen < 7 ? hexLen : 7;
    for (var i = 0; i < n; i++) {
      v = (v << 8) | hex[i];
    }
    return v;
  }

  /// The last hex token as UTF-16BE text (one byte is taken as a code unit).
  String get hexText {
    final n = hexLen < 32 ? hexLen : 32;
    if (n == 1) return String.fromCharCode(hex[0]);
    final units = <int>[
      for (var i = 0; i + 1 < n; i += 2) (hex[i] << 8) | hex[i + 1],
    ];
    return String.fromCharCodes(units);
  }

  void run() {
    while (true) {
      final t = next();
      if (t == _Tok.eof) return;
      if (t != _Tok.keyword) continue;
      switch (word) {
        case 'begincodespacerange':
          _codespace();
        case 'beginbfchar':
          if (!_bfchar()) return;
        case 'beginbfrange':
          if (!_bfrange()) return;
      }
    }
  }

  void _codespace() {
    while (true) {
      var t = next();
      if (t != _Tok.hex) return;
      final len = hexLen, lo = hexInt;
      t = next();
      if (t != _Tok.hex) return;
      if (len >= 1 && len <= 4 && map.codespace.length < 64) {
        map.codespace.add((len, lo, hexInt));
      }
    }
  }

  bool _bfchar() {
    while (true) {
      var t = next();
      if (t != _Tok.hex) return true;
      final len = hexLen, code = hexInt;
      t = next();
      if (t != _Tok.hex) {
        if (t == _Tok.eof) return true;
        continue; // `<src> /glyphname`: no Unicode value.
      }
      if (budget.take(1) < 1) {
        map.truncated = true;
        return false;
      }
      if (len >= 1 && len <= 4) map._putText(len, code, hexText);
    }
  }

  bool _bfrange() {
    while (true) {
      var t = next();
      if (t != _Tok.hex) return true;
      final len = hexLen, lo = hexInt;
      t = next();
      if (t != _Tok.hex) return true;
      final hi = hexInt;
      t = next();
      final valid = len >= 1 && len <= 4 && hi >= lo;
      if (t == _Tok.hex) {
        if (!valid) continue;
        final dst = hexText;
        if (dst.isEmpty) continue;
        var span = hi - lo + 1;
        if (span > maxRangeExpansion) span = maxRangeExpansion;
        span = budget.take(span);
        if (span == 0) {
          map.truncated = true;
          return false;
        }
        final last = dst.codeUnitAt(dst.length - 1);
        final head = dst.substring(0, dst.length - 1);
        for (var i = 0; i < span; i++) {
          final u = last + i;
          // keep the sequence valid: the last unit does not leave the BMP.
          if (u > 0xFFFF) break;
          if (head.isEmpty && (u < 0xD800 || u > 0xDFFF)) {
            map._put(len, lo + i, u);
          } else {
            map._putText(len, lo + i, head + String.fromCharCode(u));
          }
        }
        if (span < hi - lo + 1) {
          map.truncated = true;
          if (budget.exhausted) return false;
        }
      } else if (t == _Tok.arrayOpen) {
        var i = 0;
        while (true) {
          t = next();
          if (t != _Tok.hex) break; // `]`, or garbage that ends the array.
          if (!valid || i >= maxRangeExpansion || lo + i > hi) continue;
          if (budget.take(1) < 1) {
            map.truncated = true;
            return false;
          }
          map._putText(len, lo + i, hexText);
          i++;
        }
      } else if (t == _Tok.eof) {
        return true;
      }
    }
  }
}
