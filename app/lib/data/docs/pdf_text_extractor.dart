/// A minimal PDF text extractor on top of the vendored `pdf_cos` only.
///
/// It exists because text extraction needs none of what a full PDF stack
/// builds: font programs, images, patterns, colour spaces, rendering. Those
/// parsers allocate from counts written in the file (a Type 1 `/Subrs 3e8`
/// became a 1.6 GB `List.filled`), and no watchdog can interrupt a single
/// allocation. This code never opens a `FontFile`, `FontFile2`, `FontFile3`,
/// `CIDToGIDMap`, ICC profile, pattern, image or shading. It reads:
///
/// * the page tree (iterative, cycle-safe, [maxPdfTextPages] pages, depth
///   [maxPageTreeDepth]),
/// * page and form content streams, decoded by `pdf_cos` under its shared
///   `DecodeBudget` and tokenised by its bounded `ContentStreamParser`,
/// * per font only: `/ToUnicode`, `/Encoding` (+ `/Differences`),
///   `/Widths`/`/W` (for spacing), `/FontDescriptor` `/Flags` and
///   `/MissingWidth`.
///
/// Every allocation sized from file data is clamped by the input length or a
/// constant (see `pdf_cmap.dart` for tables). Identity-H/V fonts without a
/// `/ToUnicode` yield no text.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'pdf_cmap.dart';
import 'pdf_encodings.dart';

/// Pages read per document by default; later pages are ignored.
const maxPdfTextPages = 2000;

/// Deepest page-tree nesting followed.
const maxPageTreeDepth = 64;

/// Deepest form XObject nesting followed.
const maxFormDepth = 8;

/// Page-tree nodes visited per document.
const _maxTreeNodes = 100000;

/// Form XObject executions per document.
const _maxFormRuns = 20000;

/// Content operators executed per document, across pages and forms.
const _maxTotalOps = 20000000;

/// Content streams read per page.
const _maxStreamsPerPage = 10000;

/// Fonts built per document.
const _maxFonts = 5000;

const _maxGsDepth = 256;

/// The extracted text exceeded the character cap.
final class PdfTextTooLong implements Exception {
  const PdfTextTooLong();
}

/// Text of one document: [pageCount] pages walked, [pages] their raw text
/// (index = page number - 1, empty for a page with no text).
final class PdfTextResult {
  final int pageCount;
  final List<String> pages;
  const PdfTextResult(this.pageCount, this.pages);
}

/// Extracts text from an open, unencrypted [doc]. Stops with
/// [PdfTextTooLong] past [maxChars] raw characters; `pdf_cos` limit
/// exceptions ([PdfDecodeLimitExceeded]) propagate.
PdfTextResult extractPdfText(
  CosDocument doc, {
  int maxPages = maxPdfTextPages,
  int maxChars = 1600000,
}) => _Extractor(doc, maxPages, maxChars).run();

final class _M {
  final double a, b, c, d, e, f;
  const _M(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _M(1, 0, 0, 1, 0, 0);

  /// this x [o] (row-vector convention, as in the PDF spec).
  _M mul(_M o) => _M(
    a * o.a + b * o.c,
    a * o.b + b * o.d,
    c * o.a + d * o.c,
    c * o.b + d * o.d,
    e * o.a + f * o.c + o.e,
    e * o.b + f * o.d + o.f,
  );
}

/// The text-related slice of the graphics state.
final class _Gs {
  _M ctm;
  double tc, tw, th, tl;
  _Font? font;
  double fs;
  _Gs(this.ctm, this.tc, this.tw, this.th, this.tl, this.font, this.fs);
  _Gs copy() => _Gs(ctm, tc, tw, th, tl, font, fs);
}

final class _Font {
  _Font({
    required this.composite,
    this.toUni,
    this.table,
    this.utf16 = false,
    this.widths,
    this.firstChar = 0,
    this.defaultWidth = 500,
    this.cidWidths,
    this.widthScale = 1,
  });

  final bool composite;
  final ToUnicodeMap? toUni;

  /// Simple fonts: code -> text.
  final List<String?>? table;

  /// Composite fonts with a UCS-2/UTF-16 predefined CMap and no ToUnicode.
  final bool utf16;

  final List<double>? widths;
  final int firstChar;
  final double defaultWidth;
  final Map<int, double>? cidWidths;
  final double widthScale;

  int codeLength(Uint8List s, int pos) {
    if (!composite) return 1;
    final t = toUni;
    if (t != null) return t.codeLength(s, pos);
    return pos + 2 <= s.length ? 2 : 1;
  }

  String? text(int code, int len) {
    if (!composite) {
      final tb = table;
      return tb != null && code < tb.length ? tb[code] : null;
    }
    final t = toUni;
    if (t != null) {
      final s = t.lookup(code, len);
      if (s != null) return s;
    }
    if (utf16 && len == 2) return String.fromCharCode(code);
    return null;
  }

  /// Glyph advance in 1/1000 text-space units.
  double width(int code) {
    if (composite) return cidWidths?[code] ?? defaultWidth;
    final w = widths;
    if (w != null) {
      final i = code - firstChar;
      if (i >= 0 && i < w.length) return w[i] * widthScale;
    }
    return code == 32 ? defaultWidth * 0.55 : defaultWidth;
  }
}

final class _Extractor {
  _Extractor(this.doc, this.maxPages, this.maxChars);

  final CosDocument doc;
  final int maxPages;
  final int maxChars;
  final PdfTableBudget _tables = PdfTableBudget();
  final Map<int, _Font?> _fontsByRef = {};
  final Map<CosDictionary, _Font?> _fontsByDict = Map.identity();
  int _fontCount = 0;
  int _ops = 0;
  int _formRuns = 0;
  int _chars = 0;

  // --- object helpers -----------------------------------------------------

  CosDictionary? _dict(CosObject? o) {
    final r = doc.resolve(o);
    return r is CosDictionary ? r : (r is CosStream ? r.dictionary : null);
  }

  String? _name(CosObject? o) {
    final r = doc.resolve(o);
    return r is CosName ? r.value : null;
  }

  num? _numOf(CosObject? o) {
    final r = doc.resolve(o);
    return r is CosInteger ? r.value : (r is CosReal ? r.value : null);
  }

  // --- page tree ----------------------------------------------------------

  PdfTextResult run() {
    final root = doc.catalog;
    final pages = <String>[];
    // (node, inherited /Resources, depth); popped last-in-first-out, kids
    // pushed in reverse so pages come out in document order.
    final stack = <(CosObject, CosObject?, int)>[
      (root['Pages'] ?? CosNull.instance, null, 0),
    ];
    final seenRefs = <int>{};
    final seenDicts = Set<CosDictionary>.identity();
    var nodes = 0;
    while (stack.isNotEmpty && pages.length < maxPages) {
      final (raw, inheritedRes, depth) = stack.removeLast();
      if (++nodes > _maxTreeNodes || depth > maxPageTreeDepth) continue;
      if (raw is CosReference && !seenRefs.add(raw.objectNumber)) continue;
      final node = _dict(raw);
      if (node == null) continue;
      if (raw is! CosReference && !seenDicts.add(node)) continue;
      final res = node['Resources'] ?? inheritedRes;
      final kids = doc.resolve(node['Kids']);
      if (kids is CosArray) {
        for (var i = kids.length - 1; i >= 0; i--) {
          stack.add((kids[i], res, depth + 1));
        }
        continue;
      }
      pages.add(_pageText(node, res));
    }
    return PdfTextResult(pages.length, pages);
  }

  String _pageText(CosDictionary page, CosObject? resources) {
    final interp = _Interp(this);
    try {
      final contents = doc.resolve(page['Contents']);
      final streams = <CosStream>[];
      if (contents is CosStream) {
        streams.add(contents);
      } else if (contents is CosArray) {
        for (final item in contents.items) {
          // a page of that many streams is hostile, not just long.
          if (streams.length >= _maxStreamsPerPage) {
            throw const PdfDecodeLimitExceeded('too many content streams');
          }
          final s = doc.resolve(item);
          if (s is CosStream) streams.add(s);
        }
      }
      for (final s in streams) {
        interp.runStream(s, _dict(resources), 0);
      }
    } on PdfDecodeLimitExceeded {
      rethrow;
    } on PdfTextTooLong {
      rethrow;
    } on Object {
      // one bad page keeps what it produced and must not lose the rest.
    }
    return interp.out.toString();
  }

  void countChars(int n) {
    _chars += n;
    if (_chars > maxChars) throw const PdfTextTooLong();
  }

  // --- fonts ----------------------------------------------------------------

  _Font? fontFor(CosObject? raw) {
    if (raw is CosReference) {
      if (_fontsByRef.containsKey(raw.objectNumber)) {
        return _fontsByRef[raw.objectNumber];
      }
      final f = _build(_dict(raw));
      _fontsByRef[raw.objectNumber] = f;
      return f;
    }
    final d = _dict(raw);
    if (d == null) return null;
    if (_fontsByDict.containsKey(d)) return _fontsByDict[d];
    return _fontsByDict[d] = _build(d);
  }

  _Font? _build(CosDictionary? d) {
    if (d == null || ++_fontCount > _maxFonts) return null;
    final subtype = _name(d['Subtype']);
    final toUni = _toUnicode(d['ToUnicode']);
    if (subtype == 'Type0') return _composite(d, toUni);
    return _simple(d, subtype, toUni);
  }

  ToUnicodeMap? _toUnicode(CosObject? raw) {
    final s = doc.resolve(raw);
    if (s is! CosStream) return null;
    try {
      return ToUnicodeMap.parse(doc.decodeStreamData(s), _tables);
    } on PdfDecodeLimitExceeded {
      rethrow;
    } on Object {
      return null;
    }
  }

  _Font _composite(CosDictionary d, ToUnicodeMap? toUni) {
    final enc = doc.resolve(d['Encoding']);
    final encName = enc is CosName ? enc.value : '';
    final utf16 = encName.contains('UCS2') || encName.contains('UTF16');
    var dw = 1000.0;
    Map<int, double>? cid;
    final desc = doc.resolve(d['DescendantFonts']);
    final df = desc is CosArray && desc.length > 0
        ? _dict(desc[0])
        : _dict(desc);
    if (df != null) {
      dw = (_numOf(df['DW']) ?? 1000).toDouble();
      cid = _cidWidths(doc.resolve(df['W']));
    }
    return _Font(
      composite: true,
      toUni: toUni,
      utf16: utf16,
      defaultWidth: dw,
      cidWidths: cid,
    );
  }

  /// `/W`: `c [w1 w2 ...]` or `c1 c2 w`, expanded under the shared table
  /// budget and the per-range cap.
  Map<int, double>? _cidWidths(CosObject w) {
    if (w is! CosArray) return null;
    final out = <int, double>{};
    final items = w.items;
    var i = 0;
    while (i < items.length && !_tables.exhausted) {
      final first = _numOf(items[i]);
      if (first == null || i + 1 >= items.length) break;
      final next = doc.resolve(items[i + 1]);
      if (next is CosArray) {
        var c = first.toInt();
        for (final x in next.items) {
          if (_tables.take(1) < 1) break;
          final v = _numOf(x);
          if (v != null) out[c] = v.toDouble();
          c++;
        }
        i += 2;
      } else {
        final last = _numOf(next);
        final wd = i + 2 < items.length ? _numOf(items[i + 2]) : null;
        if (last == null || wd == null) break;
        final lo = first.toInt();
        var span = last.toInt() - lo + 1;
        if (span > maxRangeExpansion) span = maxRangeExpansion;
        span = span > 0 ? _tables.take(span) : 0;
        for (var k = 0; k < span; k++) {
          out[lo + k] = wd.toDouble();
        }
        i += 3;
      }
    }
    return out;
  }

  _Font _simple(CosDictionary d, String? subtype, ToUnicodeMap? toUni) {
    final enc = doc.resolve(d['Encoding']);
    final desc = _dict(d['FontDescriptor']);
    final flags = _numOf(desc?['Flags'])?.toInt() ?? 0;
    final symbolic = flags & 4 != 0 && flags & 32 == 0;
    final baseFont = _name(d['BaseFont']) ?? '';

    String? baseName;
    CosArray? diffs;
    if (enc is CosName) {
      baseName = enc.value;
    } else if (enc is CosDictionary) {
      baseName = _name(enc['BaseEncoding']);
      final df = doc.resolve(enc['Differences']);
      if (df is CosArray) diffs = df;
    }
    final hasEncoding = baseName != null || diffs != null;

    final table = List<String?>.filled(256, null);
    // A symbol font with no encoding and no ToUnicode has no text we can name.
    final unreadable =
        !hasEncoding &&
        toUni == null &&
        (baseFont.contains('Symbol') ||
            baseFont.contains('Dingbats') ||
            (subtype == 'TrueType' && symbolic));
    if (!unreadable) {
      final base = switch (baseName) {
        'WinAnsiEncoding' => winAnsiEncoding,
        'MacRomanEncoding' => macRomanEncoding,
        'StandardEncoding' || 'MacExpertEncoding' => standardEncoding,
        _ => subtype == 'TrueType' ? winAnsiEncoding : standardEncoding,
      };
      for (var c = 0; c < 256; c++) {
        if (base[c] != 0) table[c] = String.fromCharCode(base[c]);
      }
      if (diffs != null) {
        var code = 0;
        for (final item in diffs.items) {
          final o = doc.resolve(item);
          if (o is CosInteger) {
            code = o.value;
          } else if (o is CosName) {
            if (code >= 0 && code < 256) table[code] = glyphNameToText(o.value);
            code++;
          }
        }
      }
    }
    if (toUni != null) {
      for (var c = 0; c < 256; c++) {
        final s = toUni.lookup(c, 1) ?? toUni.lookup(c, 2);
        if (s != null) table[c] = s;
      }
    }

    final fc = (_numOf(d['FirstChar'])?.toInt() ?? 0).clamp(0, 255);
    List<double>? widths;
    final wa = doc.resolve(d['Widths']);
    if (wa is CosArray) {
      final n = math.min(wa.length, 256);
      widths = [for (var i = 0; i < n; i++) (_numOf(wa[i]) ?? 0).toDouble()];
    }
    var scale = 1.0;
    if (subtype == 'Type3') {
      final fm = doc.resolve(d['FontMatrix']);
      final a = fm is CosArray && fm.length > 0 ? _numOf(fm[0]) : null;
      scale = (a ?? 0.001).toDouble() * 1000;
    }
    return _Font(
      composite: false,
      table: table,
      toUni: toUni,
      widths: widths,
      firstChar: fc,
      defaultWidth: (_numOf(desc?['MissingWidth']) ?? 500).toDouble(),
      widthScale: scale,
    );
  }

  // --- form XObjects --------------------------------------------------------

  final Set<int> activeForms = {};

  bool takeFormRun() => ++_formRuns <= _maxFormRuns;

  bool takeOp() => ++_ops <= _maxTotalOps;
}

/// Executes content operators for one page, keeping the text state.
final class _Interp {
  _Interp(this.x);

  final _Extractor x;
  final StringBuffer out = StringBuffer();
  late _Gs gs = _Gs(_M.identity, 0, 0, 1, 0, null, 0);
  final List<_Gs> _stack = [];
  int _overflow = 0;
  _M _tm = _M.identity;
  _M _tlm = _M.identity;

  // Where the last glyph ended (device space) and how tall it was.
  bool _have = false;
  double _lastX = 0, _lastY = 0, _lastH = 1;
  int _last = 0x0A; // last code unit written

  void runStream(CosStream s, CosDictionary? resources, int depth) {
    final Uint8List data;
    try {
      data = x.doc.decodeStreamData(s);
    } on PdfDecodeLimitExceeded {
      rethrow;
    } on Object {
      return; // an undecodable stream contributes nothing.
    }
    final cursor = ContentStreamParser.cursor(data);
    try {
      while (true) {
        final op = cursor.nextOperation();
        if (op == null) break;
        if (!x.takeOp()) {
          throw const PdfDecodeLimitExceeded('too many content operators');
        }
        try {
          _apply(op, resources, depth);
        } on PdfDecodeLimitExceeded {
          rethrow;
        } on PdfTextTooLong {
          rethrow;
        } on Object {
          // a malformed operand costs that operator only.
        }
      }
    } on PdfDecodeLimitExceeded {
      rethrow;
    } on PdfTextTooLong {
      rethrow;
    } on Object {
      // malformed tail: keep what was read.
    }
  }

  static double? _n(List<CosObject> o, int i) {
    if (i >= o.length) return null;
    final v = o[i];
    return v is CosInteger
        ? v.value.toDouble()
        : (v is CosReal ? v.value : null);
  }

  void _apply(ContentOperation op, CosDictionary? res, int depth) {
    switch (op.operator) {
      case 'q':
        if (_stack.length >= _maxGsDepth) {
          _overflow++;
        } else {
          _stack.add(gs.copy());
        }
      case 'Q':
        if (_overflow > 0) {
          _overflow--;
        } else if (_stack.isNotEmpty) {
          gs = _stack.removeLast();
        }
      case 'cm':
        final o = op.operands;
        final m = _matrix(o, 0);
        if (m != null) gs.ctm = m.mul(gs.ctm);
      case 'BT':
        _tm = _tlm = _M.identity;
      case 'Tc':
        gs.tc = _n(op.operands, 0) ?? gs.tc;
      case 'Tw':
        gs.tw = _n(op.operands, 0) ?? gs.tw;
      case 'Tz':
        gs.th = (_n(op.operands, 0) ?? 100) / 100;
      case 'TL':
        gs.tl = _n(op.operands, 0) ?? gs.tl;
      case 'Tf':
        final o = op.operands;
        final name = o.isNotEmpty && o[0] is CosName
            ? (o[0] as CosName).value
            : null;
        gs.fs = _n(o, 1) ?? gs.fs;
        if (name != null) {
          final fonts = x._dict(res?['Font']);
          gs.font = x.fontFor(fonts?[name]);
        }
      case 'Td':
        final o = op.operands;
        _move(_n(o, 0) ?? 0, _n(o, 1) ?? 0);
      case 'TD':
        final o = op.operands;
        final ty = _n(o, 1) ?? 0;
        gs.tl = -ty;
        _move(_n(o, 0) ?? 0, ty);
      case 'T*':
        _move(0, -gs.tl);
      case 'Tm':
        final m = _matrix(op.operands, 0);
        if (m != null) _tm = _tlm = m;
      case 'Tj':
        final o = op.operands;
        if (o.isNotEmpty && o[0] is CosString) {
          _show((o[0] as CosString).bytes);
        }
      case "'":
        final o = op.operands;
        _move(0, -gs.tl);
        if (o.isNotEmpty && o[0] is CosString) {
          _show((o[0] as CosString).bytes);
        }
      case '"':
        final o = op.operands;
        gs.tw = _n(o, 0) ?? gs.tw;
        gs.tc = _n(o, 1) ?? gs.tc;
        _move(0, -gs.tl);
        if (o.length > 2 && o[2] is CosString) {
          _show((o[2] as CosString).bytes);
        }
      case 'TJ':
        final o = op.operands;
        if (o.isEmpty || o[0] is! CosArray) return;
        for (final item in (o[0] as CosArray).items) {
          if (item is CosString) {
            _show(item.bytes);
          } else if (item is CosInteger || item is CosReal) {
            final k = item is CosInteger
                ? item.value.toDouble()
                : (item as CosReal).value;
            _advance(-k / 1000 * gs.fs * gs.th);
          }
        }
      case 'Do':
        final o = op.operands;
        if (o.isNotEmpty && o[0] is CosName) {
          _doForm((o[0] as CosName).value, res, depth);
        }
    }
  }

  static _M? _matrix(List<CosObject> o, int at) {
    final v = [for (var i = 0; i < 6; i++) _n(o, at + i)];
    if (v.any((e) => e == null)) return null;
    return _M(v[0]!, v[1]!, v[2]!, v[3]!, v[4]!, v[5]!);
  }

  void _move(double tx, double ty) {
    _tlm = _M(1, 0, 0, 1, tx, ty).mul(_tlm);
    _tm = _tlm;
  }

  void _advance(double tx) {
    _tm = _M(1, 0, 0, 1, tx, 0).mul(_tm);
  }

  void _emit(String s) {
    if (s.isEmpty) return;
    x.countChars(s.length);
    out.write(s);
    _last = s.codeUnitAt(s.length - 1);
  }

  /// Puts a space or a line break before the next glyph when it lands away
  /// from where the previous one ended.
  void _separate(_M t, double h) {
    if (!_have) return;
    final dx = t.e - _lastX, dy = t.f - _lastY;
    final len = math.sqrt(t.a * t.a + t.b * t.b);
    final ux = len > 1e-9 ? t.a / len : 1.0;
    final uy = len > 1e-9 ? t.b / len : 0.0;
    final along = dx * ux + dy * uy;
    final across = -dx * uy + dy * ux;
    final ref = math.max(h, _lastH);
    if (across.abs() > 0.5 * ref || along < -2 * ref) {
      if (_last != 0x0A) _emit('\n');
    } else if (along > 0.18 * ref && _last != 0x20 && _last != 0x0A) {
      _emit(' ');
    }
  }

  void _show(Uint8List bytes) {
    final font = gs.font;
    if (font == null || bytes.isEmpty) return;
    final fs = gs.fs;
    var t = _tm.mul(gs.ctm);
    final h = fs.abs() * math.sqrt(t.c * t.c + t.d * t.d);
    var first = true;
    var i = 0;
    while (i < bytes.length) {
      final len = font.codeLength(bytes, i);
      var code = 0;
      for (var k = 0; k < len && i + k < bytes.length; k++) {
        code = (code << 8) | bytes[i + k];
      }
      i += len;
      final s = font.text(code, len);
      if (s != null && s.isNotEmpty) {
        if (first) {
          _separate(t, h > 0 ? h : 1);
          first = false;
        }
        _emit(s.contains('\u0000') ? s.replaceAll('\u0000', '') : s);
      }
      final space = len == 1 && code == 32 ? gs.tw : 0.0;
      _advance((font.width(code) / 1000 * fs + gs.tc + space) * gs.th);
    }
    t = _tm.mul(gs.ctm);
    _lastX = t.e;
    _lastY = t.f;
    _lastH = h > 0 ? h : 1;
    _have = true;
  }

  void _doForm(String name, CosDictionary? res, int depth) {
    if (depth >= maxFormDepth) return;
    final xobjs = x._dict(res?['XObject']);
    final raw = xobjs?[name];
    if (raw is! CosReference) return;
    if (x.activeForms.contains(raw.objectNumber)) return;
    final obj = x.doc.resolve(raw);
    if (obj is! CosStream || x._name(obj.dictionary['Subtype']) != 'Form') {
      return;
    }
    if (!x.takeFormRun()) return;
    final saved = gs.copy();
    final savedTm = _tm, savedTlm = _tlm;
    final savedStack = _stack.length, savedOverflow = _overflow;
    final fm = x.doc.resolve(obj.dictionary['Matrix']);
    if (fm is CosArray) {
      final m = _matrix(fm.items, 0);
      if (m != null) gs.ctm = m.mul(gs.ctm);
    }
    final formRes = x._dict(obj.dictionary['Resources']) ?? res;
    x.activeForms.add(raw.objectNumber);
    try {
      runStream(obj, formRes, depth + 1);
    } finally {
      x.activeForms.remove(raw.objectNumber);
      gs = saved;
      _tm = savedTm;
      _tlm = savedTlm;
      while (_stack.length > savedStack) {
        _stack.removeLast();
      }
      _overflow = savedOverflow;
    }
  }
}
