/// Simple-font encodings for PDF text extraction: StandardEncoding,
/// WinAnsiEncoding and MacRomanEncoding as 256-entry tables of code points
/// (0 = no character), and glyph names (for /Differences) to Unicode through
/// a compact subset of the Adobe Glyph List.
///
/// Pure tables and lookups. Nothing here reads a font program.
library;

const _asciiNames =
    'space exclam quotedbl numbersign dollar percent ampersand quotesingle '
    'parenleft parenright asterisk plus comma hyphen period slash zero one '
    'two three four five six seven eight nine colon semicolon less equal '
    'greater question at';

const _asciiNames2 =
    'bracketleft backslash bracketright asciicircum '
    'underscore grave';

const _asciiNames3 = 'braceleft bar braceright asciitilde';

// Latin-1 0xA0..0xBF and 0xC0..0xFF in code order.
const _latin1Names =
    'space exclamdown cent sterling currency yen brokenbar '
    'section dieresis copyright ordfeminine guillemotleft logicalnot hyphen '
    'registered macron degree plusminus twosuperior threesuperior acute mu '
    'paragraph periodcentered cedilla onesuperior ordmasculine guillemotright '
    'onequarter onehalf threequarters questiondown '
    'Agrave Aacute Acircumflex Atilde Adieresis Aring AE Ccedilla Egrave '
    'Eacute Ecircumflex Edieresis Igrave Iacute Icircumflex Idieresis Eth '
    'Ntilde Ograve Oacute Ocircumflex Otilde Odieresis multiply Oslash Ugrave '
    'Uacute Ucircumflex Udieresis Yacute Thorn germandbls agrave aacute '
    'acircumflex atilde adieresis aring ae ccedilla egrave eacute ecircumflex '
    'edieresis igrave iacute icircumflex idieresis eth ntilde ograve oacute '
    'ocircumflex otilde odieresis divide oslash ugrave uacute ucircumflex '
    'udieresis yacute thorn ydieresis';

const _extraNames = <String, int>{
  'Euro': 0x20AC,
  'endash': 0x2013,
  'emdash': 0x2014,
  'bullet': 0x2022,
  'ellipsis': 0x2026,
  'quoteleft': 0x2018,
  'quoteright': 0x2019,
  'quotedblleft': 0x201C,
  'quotedblright': 0x201D,
  'quotesinglbase': 0x201A,
  'quotedblbase': 0x201E,
  'dagger': 0x2020,
  'daggerdbl': 0x2021,
  'perthousand': 0x2030,
  'guilsinglleft': 0x2039,
  'guilsinglright': 0x203A,
  'trademark': 0x2122,
  'fi': 0xFB01,
  'fl': 0xFB02,
  'ff': 0xFB00,
  'ffi': 0xFB03,
  'ffl': 0xFB04,
  'florin': 0x0192,
  'circumflex': 0x02C6,
  'tilde': 0x02DC,
  'breve': 0x02D8,
  'dotaccent': 0x02D9,
  'ring': 0x02DA,
  'ogonek': 0x02DB,
  'caron': 0x02C7,
  'hungarumlaut': 0x02DD,
  'dotlessi': 0x0131,
  'Lslash': 0x0141,
  'lslash': 0x0142,
  'OE': 0x0152,
  'oe': 0x0153,
  'Scaron': 0x0160,
  'scaron': 0x0161,
  'Zcaron': 0x017D,
  'zcaron': 0x017E,
  'Ydieresis': 0x0178,
  'fraction': 0x2044,
  'minus': 0x2212,
  'nbspace': 0x00A0,
  'nonbreakingspace': 0x00A0,
  'sfthyphen': 0x00AD,
  'softhyphen': 0x00AD,
  'alpha': 0x03B1,
  'beta': 0x03B2,
  'gamma': 0x03B3,
  'delta': 0x03B4,
  'epsilon': 0x03B5,
  'theta': 0x03B8,
  'lambda': 0x03BB,
  'pi': 0x03C0,
  'sigma': 0x03C3,
  'phi': 0x03C6,
  'omega': 0x03C9,
  'Delta': 0x2206,
  'Omega': 0x2126,
  'infinity': 0x221E,
  'summation': 0x2211,
  'product': 0x220F,
  'radical': 0x221A,
  'integral': 0x222B,
  'approxequal': 0x2248,
  'notequal': 0x2260,
  'lessequal': 0x2264,
  'greaterequal': 0x2265,
  'partialdiff': 0x2202,
  'arrowleft': 0x2190,
  'arrowup': 0x2191,
  'arrowright': 0x2192,
  'arrowdown': 0x2193,
  'rupee': 0x20B9,
};

final Map<String, int> _glyphs = () {
  final m = <String, int>{..._extraNames};
  void names(String list, int first) {
    var i = first;
    for (final n in list.split(' ')) {
      m.putIfAbsent(n, () => i);
      i++;
    }
  }

  // ASCII first so `hyphen` keeps U+002D, as in the Adobe Glyph List.
  names(_asciiNames, 0x20);
  names(_asciiNames2, 0x5B);
  names(_asciiNames3, 0x7B);
  for (var c = 0x41; c <= 0x5A; c++) {
    m[String.fromCharCode(c)] = c;
  }
  for (var c = 0x61; c <= 0x7A; c++) {
    m[String.fromCharCode(c)] = c;
  }
  names(_latin1Names, 0xA0);
  return m;
}();

bool _hex(String s) => RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s);

bool _scalar(int cp) =>
    cp > 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF);

String? _component(String c) {
  final cp = _glyphs[c];
  if (cp != null) return String.fromCharCode(cp);
  // uniXXXX, or several of them back to back (a UTF-16 sequence).
  if (c.startsWith('uni') &&
      c.length >= 7 &&
      (c.length - 3) % 4 == 0 &&
      c.length <= 3 + 4 * 8 &&
      _hex(c.substring(3))) {
    final units = <int>[
      for (var i = 3; i < c.length; i += 4)
        int.parse(c.substring(i, i + 4), radix: 16),
    ];
    return String.fromCharCodes(units);
  }
  // uXXXX .. uXXXXXX
  if (c.startsWith('u') &&
      c.length >= 5 &&
      c.length <= 7 &&
      _hex(c.substring(1))) {
    final v = int.parse(c.substring(1), radix: 16);
    return _scalar(v) ? String.fromCharCode(v) : null;
  }
  return null;
}

/// The text a glyph name stands for, or null when unknown (`.notdef`,
/// `g12`, `cid41`, ...). Handles `f_i` ligature composites and `.alt`
/// suffixes.
String? glyphNameToText(String name) {
  if (name.isEmpty || name.length > 64) return null;
  final dot = name.indexOf('.');
  final base = dot < 0 ? name : name.substring(0, dot);
  if (base.isEmpty) return null;
  final parts = base.split('_');
  if (parts.length == 1) return _component(base);
  final out = StringBuffer();
  for (final p in parts) {
    final t = _component(p);
    if (t == null) return null;
    out.write(t);
  }
  return out.toString();
}

// cp1252 for 0x80..0x9F (0 = undefined).
const _cp1252High = <int>[
  0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0, //
  0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178, //
];

/// WinAnsiEncoding (code -> code point, 0 = none).
final List<int> winAnsiEncoding = () {
  final t = List<int>.filled(256, 0);
  for (var c = 0x20; c <= 0x7E; c++) {
    t[c] = c;
  }
  for (var c = 0x80; c <= 0x9F; c++) {
    t[c] = _cp1252High[c - 0x80];
  }
  for (var c = 0xA0; c <= 0xFF; c++) {
    t[c] = c;
  }
  t[0xA0] = 0x20;
  t[0xAD] = 0x2D;
  return t;
}();

// Mac OS Roman 0x80..0xFF as PDF defines it (U+0000 = undefined).
const _macHigh =
    'ÄÅÇÉÑÖÜáàâäãåçéè' // 80
    'êëíìîïñóòôöõúùûü' // 90
    '†°¢£§•¶ß®©™´¨\u0000ÆØ' // A0
    '\u0000±\u0000\u0000¥µ\u0000\u0000\u0000\u0000\u0000ªº\u0000æø' // B0
    '¿¡¬\u0000ƒ\u0000\u0000«»… ÀÃÕŒœ' // C0
    '–—“”‘’÷\u0000ÿŸ⁄¤‹›ﬁﬂ' // D0
    '‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔ' // E0
    '\u0000ÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ'; // F0

/// MacRomanEncoding.
final List<int> macRomanEncoding = () {
  final t = List<int>.filled(256, 0);
  for (var c = 0x20; c <= 0x7E; c++) {
    t[c] = c;
  }
  for (var i = 0; i < 128; i++) {
    t[0x80 + i] = _macHigh.codeUnitAt(i);
  }
  t[0xCA] = 0x20;
  return t;
}();

const _standardHigh = <int, String>{
  0xA1: 'exclamdown', 0xA2: 'cent', 0xA3: 'sterling', 0xA4: 'fraction', //
  0xA5: 'yen', 0xA6: 'florin', 0xA7: 'section', 0xA8: 'currency',
  0xA9: 'quotesingle', 0xAA: 'quotedblleft', 0xAB: 'guillemotleft',
  0xAC: 'guilsinglleft', 0xAD: 'guilsinglright', 0xAE: 'fi', 0xAF: 'fl',
  0xB1: 'endash', 0xB2: 'dagger', 0xB3: 'daggerdbl', 0xB4: 'periodcentered',
  0xB6: 'paragraph', 0xB7: 'bullet', 0xB8: 'quotesinglbase',
  0xB9: 'quotedblbase', 0xBA: 'quotedblright', 0xBB: 'guillemotright',
  0xBC: 'ellipsis', 0xBD: 'perthousand', 0xBF: 'questiondown', 0xC1: 'grave',
  0xC2: 'acute', 0xC3: 'circumflex', 0xC4: 'tilde', 0xC5: 'macron',
  0xC6: 'breve', 0xC7: 'dotaccent', 0xC8: 'dieresis', 0xCA: 'ring',
  0xCB: 'cedilla', 0xCD: 'hungarumlaut', 0xCE: 'ogonek', 0xCF: 'caron',
  0xD0: 'emdash', 0xE1: 'AE', 0xE3: 'ordfeminine', 0xE8: 'Lslash',
  0xE9: 'Oslash', 0xEA: 'OE', 0xEB: 'ordmasculine', 0xF1: 'ae',
  0xF5: 'dotlessi', 0xF8: 'lslash', 0xF9: 'oslash', 0xFA: 'oe',
  0xFB: 'germandbls',
};

/// StandardEncoding.
final List<int> standardEncoding = () {
  final t = List<int>.filled(256, 0);
  for (var c = 0x20; c <= 0x7E; c++) {
    t[c] = c;
  }
  t[0x27] = 0x2019;
  t[0x60] = 0x2018;
  _standardHigh.forEach((code, name) => t[code] = _glyphs[name]!);
  return t;
}();
