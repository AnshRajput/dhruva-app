// Round 7: text extraction is a minimal extractor over the vendored pdf_cos
// alone (no pdf_document / pdf_graphics). These tests cover what it reads
// (text operators, ToUnicode, simple encodings, forms, the page tree) and the
// hostile shapes that broke earlier rounds: a Type 1 font program with
// `/Subrs 300000000` (the round-6 repro; the font program must never be
// read), bfrange expansion bombs, cyclic page trees, recursive forms, and
// xref streams that spin entries out of no input.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:dhruva/data/docs/pdf_cmap.dart';
import 'package:dhruva/data/docs/pdf_encodings.dart';
import 'package:dhruva/data/docs/pdf_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';

import '../../support/pdf_builder.dart';

const _mb = 1024 * 1024;

String _text(Uint8List pdf) =>
    extractPdfText(CosDocument.open(pdf)).pages.join('\n');

PdfTextResult _result(Uint8List pdf) => extractPdfText(CosDocument.open(pdf));

typedef _Outcome = ({String outcome, double peakGrowthMb});

/// The production entry point, with the peak growth of process RSS sampled
/// every 10 ms (JIT numbers; the AOT numbers come from tool/extract_rss.dart).
Future<_Outcome> _run(String label, Uint8List pdf) async {
  final dir = await Directory.systemTemp.createTemp('dhruva_r7');
  final file = File('${dir.path}/$label.pdf')..writeAsBytesSync(pdf);
  final baseline = ProcessInfo.currentRss;
  var peak = baseline;
  final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
    final r = ProcessInfo.currentRss;
    if (r > peak) peak = r;
  });
  String outcome;
  try {
    final d = await extractDocumentFile(file.path, '$label.pdf');
    outcome = 'ok(${d.charCount})';
  } on DocumentException catch (e) {
    outcome = e.kind.name;
  } finally {
    sampler.cancel();
    await dir.delete(recursive: true);
  }
  final growth = (peak - baseline) / _mb;
  // ignore: avoid_print
  print('RSS $label: $outcome peakGrowth=${growth.toStringAsFixed(0)} MB');
  return (outcome: outcome, peakGrowthMb: growth);
}

// Type 1 font program as the round-6 repro built it (eexec-encrypted private
// dict with `/Subrs N array`).
Uint8List _eexec(List<int> plain, int r) {
  const c1 = 52845, c2 = 22719;
  final out = <int>[];
  for (final p in [0, 0, 0, 0, ...plain]) {
    final c = p ^ (r >> 8);
    r = ((c + r) * c1 + c2) & 0xFFFF;
    out.add(c);
  }
  return Uint8List.fromList(out);
}

PdfStreamBody _type1Program(int subrs) {
  final cs = _eexec([0, 0, 0, 0, 0x8b, 0x8b, 0x0d, 0x0e], 4330).sublist(4);
  final priv = BytesBuilder()
    ..add(
      latin1.encode(
        'dup /Private 8 dict dup begin /RD {string currentfile exch '
        'readstring pop} executeonly def /ND {noaccess def} executeonly def '
        '/NP {noaccess put} executeonly def\n/Subrs $subrs array\n'
        '/CharStrings 1 dict dup begin\n/a ${cs.length} RD ',
      ),
    )
    ..add(cs)
    ..add(latin1.encode(' ND\nend end\n'));
  final clear = latin1.encode(
    '%!PS-AdobeFont-1.0: X 1.0\n/FontName /X def\n'
    '/FontMatrix [0.001 0 0 0.001 0 0] readonly def\n/Encoding 256 array\n'
    '0 1 255 {1 index exch /.notdef put} for\ndup 97 /a put\nreadonly def\n'
    'currentfile eexec\n',
  );
  final enc = _eexec(priv.takeBytes(), 55665);
  return PdfStreamBody(
    '/Length1 ${clear.length} /Length2 ${enc.length} /Length3 0',
    [...clear, ...enc],
  );
}

void main() {
  group('simple fonts', () {
    test('plain text, with WinAnsi accents and curly quotes', () {
      final pdf = buildOnePagePdf(
        r'BT /F1 12 Tf 72 720 Td (caf\351 \223quoted\224 \200 5) Tj ET',
      );
      expect(_text(pdf), 'café “quoted” € 5');
    });

    test('MacRomanEncoding', () {
      final pdf = buildOnePagePdf(
        r'BT /F1 12 Tf (caf\216 na\225ve) Tj ET',
        font:
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /MacRomanEncoding >>',
      );
      expect(_text(pdf), 'café naïve');
    });

    test('/Differences with glyph names, uniXXXX and ligatures', () {
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf <4142434445> Tj ET',
        font:
            '<< /Type /Font /Subtype /Type1 /BaseFont /Custom /Encoding '
            '<< /Type /Encoding /BaseEncoding /WinAnsiEncoding '
            '/Differences [65 /uni0042 /fi /f_l /Euro /u1F600] >> >>',
      );
      expect(_text(pdf), 'Bﬁfl€\u{1F600}');
    });

    test('/ToUnicode wins over the encoding', () {
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf <010203> Tj ET',
        font:
            '<< /Type /Font /Subtype /Type1 /BaseFont /Custom '
            '/ToUnicode 6 0 R >>',
        extra: [
          PdfStreamBody.text('', '''
/CIDInit /ProcSet findresource begin 12 dict begin begincmap
1 begincodespacerange <00> <FF> endcodespacerange
2 beginbfchar <01> <0048> <02> <0069> endbfchar
1 beginbfrange <03> <03> <0021> endbfrange
endcmap'''),
        ],
      );
      expect(_text(pdf), 'Hi!');
    });

    test('a symbolic TrueType font with no encoding gives no text', () {
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf (abc) Tj ET',
        font:
            '<< /Type /Font /Subtype /TrueType /BaseFont /Sym '
            '/FontDescriptor 6 0 R >>',
        extra: ['<< /Type /FontDescriptor /Flags 4 /FontName /Sym >>'],
      );
      expect(_text(pdf).trim(), isEmpty);
    });
  });

  group('Type0 fonts', () {
    Uint8List type0({
      String? toUnicode,
      String encoding = '/Identity-H',
    }) => buildOnePagePdf(
      'BT /F1 12 Tf <00480069002000540068> Tj ET',
      font:
          '<< /Type /Font /Subtype /Type0 /BaseFont /X '
          '/Encoding $encoding /DescendantFonts [6 0 R] '
          '${toUnicode == null ? '' : '/ToUnicode 7 0 R'} >>',
      extra: [
        '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X /DW 600 '
            '/W [0 [500 500] 72 80 700] /CIDToGIDMap /Identity '
            '/FontDescriptor 8 0 R >>',
        PdfStreamBody.text('', toUnicode ?? ''),
        '<< /Type /FontDescriptor /FontName /X /Flags 4 /FontFile2 9 0 R >>',
        PdfStreamBody.text('/Length1 5', 'junk!'),
      ],
    );

    test('Identity-H with a ToUnicode bfrange', () {
      final pdf = type0(
        toUnicode:
            '1 begincodespacerange <0000> <FFFF> endcodespacerange\n'
            '1 beginbfrange <0000> <00FF> <0000> endbfrange',
      );
      expect(_text(pdf), 'Hi Th');
    });

    test('Identity-H without ToUnicode is unreadable', () {
      expect(_text(type0()).trim(), isEmpty);
      expect(
        () => extractDocumentBytes(type0(), 'a.pdf'),
        throwsA(
          isA<DocumentException>().having(
            (e) => e.kind,
            'kind',
            DocumentFailureKind.noText,
          ),
        ),
      );
    });

    test('a UCS2 predefined CMap needs no ToUnicode', () {
      expect(_text(type0(encoding: '/UniJIS-UCS2-H')), 'Hi Th');
    });

    test('a ToUnicode ligature (several characters per code)', () {
      final pdf = type0(
        toUnicode:
            '1 begincodespacerange <0000> <FFFF> endcodespacerange\n'
            '1 beginbfchar <0048> <00660069> endbfchar',
      );
      expect(_text(pdf), startsWith('fi'));
    });
  });

  group('text layout', () {
    test('TJ kerning: a wide gap is a space, a small one is not', () {
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf [(Hello)-300(world) -20 (ly)] TJ ET',
      );
      expect(_text(pdf), 'Hello worldly');
    });

    test('Td/T*/Tm/\'/" break lines, same-line moves become spaces', () {
      final pdf = buildOnePagePdf('''
BT /F1 12 Tf 14 TL 72 720 Td (one) Tj 0 -14 Td (two) Tj T* (three) Tj
(four) ' 1 0 0 1 72 600 Tm (five) Tj 90 0 Td (six) Tj
1 2 (seven) " ET''');
      expect(_text(pdf), 'one\ntwo\nthree\nfour\nfive six\nseven');
    });

    test('the CTM does not fake line breaks', () {
      final pdf = buildOnePagePdf(
        '1 0 0 -1 0 792 cm BT /F1 12 Tf 72 100 Td (up) Tj 30 0 Td (side) Tj '
        'ET',
      );
      expect(_text(pdf), 'up side');
    });

    test('text across two content streams of one page', () {
      final pdf = buildPdfObjects([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [4 0 R] /Count 1 >>',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        '<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 3 0 R >> >> '
            '/Contents [5 0 R 6 0 R] >>',
        PdfStreamBody.text('', 'BT /F1 12 Tf 72 700 Td (first) Tj'),
        PdfStreamBody.text('', '0 -20 Td (second) Tj ET'),
      ]);
      expect(_text(pdf), 'first\nsecond');
    });

    test('Resources inherited from the /Pages node', () {
      final pdf = buildPdfObjects([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [4 0 R] /Count 1 '
            '/Resources << /Font << /F1 3 0 R >> >> >>',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        '<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>',
        PdfStreamBody.text('', 'BT /F1 12 Tf (inherited) Tj ET'),
      ]);
      expect(_text(pdf), 'inherited');
    });
  });

  group('page tree', () {
    test('page tags and counts across a nested tree', () {
      final pdf = buildPdfObjects([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 3 >>',
        '<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R] /Count 2 >>',
        '<< /Type /Page /Parent 3 0 R /Contents 8 0 R '
            '/Resources << /Font << /F1 9 0 R >> >> >>',
        '<< /Type /Page /Parent 3 0 R /Contents 10 0 R '
            '/Resources << /Font << /F1 9 0 R >> >> >>',
        '<< /Type /Page /Parent 2 0 R /Contents 11 0 R '
            '/Resources << /Font << /F1 9 0 R >> >> >>',
        '<< >>',
        PdfStreamBody.text(
          '',
          'BT /F1 12 Tf (alpha page one, with enough words to count) Tj ET',
        ),
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        PdfStreamBody.text(
          '',
          'BT /F1 12 Tf (beta page two, with enough words to count) Tj ET',
        ),
        PdfStreamBody.text(
          '',
          'BT /F1 12 Tf (gamma page three, with enough words to count) Tj ET',
        ),
      ]);
      final r = _result(pdf);
      expect(r.pageCount, 3);
      expect(r.pages, [
        'alpha page one, with enough words to count',
        'beta page two, with enough words to count',
        'gamma page three, with enough words to count',
      ]);
      final doc = extractDocumentBytes(pdf, 'tree.pdf');
      expect(doc.pageCount, 3);
      expect(doc.chunks.map((c) => c.page).toSet(), {
        1,
        2,
        3,
      }, reason: 'chunks carry [p.N] tags');
    });

    test('a /Kids cycle (self, mutual) terminates with each page once', () {
      final pdf = buildPdfObjects([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [2 0 R 3 0 R 2 0 R 6 0 R] /Count 1 >>',
        '<< /Type /Pages /Parent 2 0 R /Kids [2 0 R 6 0 R] /Count 1 >>',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        PdfStreamBody.text('', 'BT /F1 12 Tf (only once) Tj ET'),
        '<< /Type /Page /Parent 3 0 R /Contents 5 0 R '
            '/Resources << /Font << /F1 4 0 R >> >> >>',
      ]);
      final r = _result(pdf);
      expect(r.pageCount, 1);
      expect(r.pages.single, 'only once');
    });

    test('a tree deeper than $maxPageTreeDepth levels is not followed', () {
      const depth = 100;
      // node i (object i + 2) has the next node as its only kid; the page is
      // object depth + 2.
      final bodies = <Object>['<< /Type /Catalog /Pages 2 0 R >>'];
      for (var i = 0; i < depth; i++) {
        bodies.add('<< /Type /Pages /Kids [${i + 3} 0 R] /Count 1 >>');
      }
      bodies
        ..add(
          '<< /Type /Page /Contents ${depth + 3} 0 R '
          '/Resources << /Font << /F1 ${depth + 4} 0 R >> >> >>',
        )
        ..add(PdfStreamBody.text('', 'BT /F1 12 Tf (too deep) Tj ET'))
        ..add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
      expect(_result(buildPdfObjects(bodies)).pageCount, 0);
    });

    test('the page cap bounds the work', () {
      // 3 real pages, cap of 2.
      final pdf = buildPdfObjects([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R 3 0 R 4 0 R 5 0 R] /Count 3 >>',
        '<< /Type /Page >>',
        '<< /Type /Page >>',
        '<< /Type /Page >>',
      ]);
      expect(extractPdfText(CosDocument.open(pdf), maxPages: 2).pageCount, 2);
    });
  });

  group('form XObjects', () {
    PdfStreamBody form(String content, String resources) => PdfStreamBody.text(
      '/Type /XObject /Subtype /Form /BBox [0 0 100 100] '
      '/Resources << $resources >>',
      content,
    );

    test('text inside a form is read, images are ignored', () {
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf (before) Tj ET /Fm1 Do /Im1 Do '
        'BT /F1 12 Tf 0 -20 Td (after) Tj ET',
        resources: '/Font << /F1 3 0 R >> /XObject << /Fm1 6 0 R /Im1 7 0 R >>',
        extra: [
          form(
            'BT /F1 12 Tf 0 -10 Td (inside the form) Tj ET',
            '/Font << /F1 3 0 R >>',
          ),
          PdfStreamBody.text(
            '/Type /XObject /Subtype /Image /Width 1 /Height 1 '
                '/ColorSpace /DeviceGray /BitsPerComponent 8',
            'x',
          ),
        ],
      );
      expect(_text(pdf), 'before\ninside the form\nafter');
    });

    test('a form that invokes itself runs once', () {
      final pdf = buildOnePagePdf(
        '/Fm1 Do',
        resources: '/Font << /F1 3 0 R >> /XObject << /Fm1 6 0 R >>',
        extra: [
          form(
            'BT /F1 12 Tf (loop) Tj ET /Fm1 Do /Fm2 Do',
            '/Font << /F1 3 0 R >> /XObject << /Fm1 6 0 R /Fm2 7 0 R >>',
          ),
          form(
            'BT /F1 12 Tf 0 -20 Td (peer) Tj ET /Fm1 Do',
            '/Font << /F1 3 0 R >> /XObject << /Fm1 6 0 R >>',
          ),
        ],
      );
      expect(_text(pdf), 'loop\npeer');
    });

    test('nesting stops at $maxFormDepth levels', () {
      const n = 14;
      final extra = <Object>[
        for (var i = 0; i < n; i++)
          form(
            'BT /F1 12 Tf (Q${i}Q) Tj ET /Next Do',
            '/Font << /F1 3 0 R >> /XObject << /Next ${7 + i} 0 R >>',
          ),
      ];
      final pdf = buildOnePagePdf(
        '/Fm1 Do',
        resources: '/Font << /F1 3 0 R >> /XObject << /Fm1 6 0 R >>',
        extra: extra,
      );
      final t = _text(pdf);
      expect(t, contains('Q0Q'));
      expect(t, contains('Q${maxFormDepth - 1}Q'));
      expect(t, isNot(contains('Q${maxFormDepth}Q')));
    });
  });

  group('hostile input', () {
    test('round-6 repro: a Type 1 FontFile with /Subrs 300000000', () async {
      for (final subrs in [10, 25000000, 300000000]) {
        final pdf = buildOnePagePdf(
          'BT /F1 12 Tf (aaaa hello there this is some body text, long '
          'enough to be a readable page) Tj ET',
          resources: '/Font << /F1 6 0 R >>',
          extra: [
            '<< /Type /Font /Subtype /Type1 /BaseFont /XXXXXX+Custom '
                '/FirstChar 97 /LastChar 97 /FontDescriptor 7 0 R >>',
            '<< /Type /FontDescriptor /FontName /XXXXXX+Custom /Flags 4 '
                '/FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 800 '
                '/Descent -200 /CapHeight 700 /StemV 80 /FontFile 8 0 R >>',
            _type1Program(subrs),
          ],
        );
        expect(pdf.length, lessThan(8192));
        final r = await _run('t1_$subrs', pdf);
        expect(r.outcome, startsWith('ok('), reason: 'subrs $subrs');
        expect(r.peakGrowthMb, lessThan(100), reason: 'subrs $subrs');
      }
    });

    test('FontFile2 / CIDToGIDMap / ICC / image streams are never decoded', () {
      // Each is a stream that could not be decoded without tripping the
      // budget (a Flate stream of zeros past the stage cap); had the
      // extractor touched one, the budget would be tripped.
      final bomb = ZLibEncoder(level: 9).convert(Uint8List(8 * _mb));
      final stream = PdfStreamBody('/Filter /FlateDecode', bomb);
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf (readable text on a page that has plenty of heavy '
        'objects hanging off it) Tj ET',
        resources:
            '/Font << /F1 3 0 R >> /ColorSpace << /Cs [/ICCBased 6 0 R] '
            '>> /XObject << /Im1 7 0 R >> /Pattern << /P1 8 0 R >> '
            '/Shading << /S1 9 0 R >>',
        font:
            '<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H '
            '/DescendantFonts [10 0 R] /ToUnicode 12 0 R >>',
        extra: [
          stream, // 6 ICC profile
          stream, // 7 image
          stream, // 8 pattern
          stream, // 9 shading
          '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X '
              '/CIDToGIDMap 11 0 R /FontDescriptor 13 0 R >>',
          stream, // 11 CIDToGIDMap
          PdfStreamBody.text(
            '',
            '1 begincodespacerange <00> <FF> endcodespacerange '
                '1 beginbfrange <00> <FF> <0000> endbfrange',
          ),
          '<< /Type /FontDescriptor /FontName /X /FontFile2 14 0 R >>',
          stream, // 14 FontFile2
        ],
      );
      final cos = CosDocument.open(pdf);
      final r = extractPdfText(cos);
      expect(r.pages.single, isNotEmpty);
      expect(cos.decodeBudget.tripped, isFalse);
      expect(cos.decodeBudget.usedBytes, lessThan(64 * 1024));
    });

    test('a bfrange expansion bomb is capped and stays small', () async {
      final unit = '<0000> <FFFF> <0041>\n';
      final cmap = StringBuffer(
        '1 begincodespacerange <0000> <FFFF> '
        'endcodespacerange\n1 beginbfrange\n',
      );
      for (var i = 0; i < 150000; i++) {
        cmap.write(unit);
      }
      cmap.write('endbfrange\n');
      final data = latin1.encode(cmap.toString());
      expect(data.length, lessThan(4 * _mb));

      final sw = Stopwatch()..start();
      final budget = PdfTableBudget();
      final map = ToUnicodeMap.parse(Uint8List.fromList(data), budget);
      expect(budget.used, lessThanOrEqualTo(maxTableEntries));
      expect(map.entryCount, lessThanOrEqualTo(maxTableEntries));
      expect(map.truncated, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));

      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf <${[for (var i = 1; i <= 60; i++) i.toRadixString(16).padLeft(4, '0')].join()}> Tj ET',
        font:
            '<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H '
            '/DescendantFonts [6 0 R] /ToUnicode 7 0 R >>',
        extra: [
          '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X /DW 500 >>',
          PdfStreamBody('', data),
        ],
      );
      final r = await _run('bfrange_bomb', pdf);
      expect(r.outcome, startsWith('ok('));
      expect(r.peakGrowthMb, lessThan(300));
    });

    test('the largest distinct table stays small and is capped', () async {
      final cmap = StringBuffer(
        '1 begincodespacerange <00000000> <FFFFFFFF> endcodespacerange\n'
        '1 beginbfrange\n',
      );
      for (var i = 0; i < 16; i++) {
        final h = i.toRadixString(16).padLeft(4, '0');
        cmap.write('<${h}0000> <${h}FFFF> <0041>\n');
      }
      cmap.write('endbfrange\n');
      final map = ToUnicodeMap.parse(
        Uint8List.fromList(latin1.encode(cmap.toString())),
        PdfTableBudget(),
      );
      expect(map.entryCount, lessThanOrEqualTo(maxTableEntries));
      expect(map.entryCount, greaterThan(900000));
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf <${'0000000100000002' * 6}> Tj ET',
        font:
            '<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H '
            '/DescendantFonts [6 0 R] /ToUnicode 7 0 R >>',
        extra: [
          '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X /DW 500 >>',
          PdfStreamBody.text('', cmap.toString()),
        ],
      );
      final r = await _run('bfrange_distinct', pdf);
      expect(r.outcome, anyOf(startsWith('ok('), 'noText'));
      expect(r.peakGrowthMb, lessThan(300));
    });

    test('one bfrange expands to at most $maxRangeExpansion entries', () {
      final map = ToUnicodeMap.parse(
        Uint8List.fromList(
          latin1.encode(
            '1 begincodespacerange <00000000> <FFFFFFFF> endcodespacerange\n'
            '1 beginbfrange <00000000> <FFFFFFFF> <0041> endbfrange',
          ),
        ),
        PdfTableBudget(),
      );
      // the last code unit stays in the BMP, so 0x41 + i stops at 0xFFFF.
      expect(map.entryCount, inInclusiveRange(65000, maxRangeExpansion));
    });

    test('a /W table is clamped too', () {
      final pdf = buildOnePagePdf(
        'BT /F1 12 Tf <0041> Tj ET',
        font:
            '<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /UniGB-UCS2-H '
            '/DescendantFonts [6 0 R] >>',
        extra: [
          '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X /DW 500 '
              '/W [${[for (var i = 0; i < 50; i++) '0 2000000000 500'].join(' ')}] >>',
        ],
      );
      expect(_text(pdf), 'A');
    });

    test('hex strings keep at most 64 bytes however long they are', () {
      final huge = '<${'0041' * 2000000}>';
      final map = ToUnicodeMap.parse(
        Uint8List.fromList(latin1.encode('1 beginbfchar <01> $huge endbfchar')),
        PdfTableBudget(),
      );
      expect(map.lookup(1, 1)!.length, lessThanOrEqualTo(32));
    });

    test('a cross-reference stream with /W [0 0 0] spins out nothing', () {
      final b = BytesBuilder();
      void w(String s) => b.add(latin1.encode(s));
      w('%PDF-1.4\n');
      w('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');
      w('2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n');
      w('3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n');
      final x = b.length;
      w(
        '4 0 obj\n<< /Type /XRef /W [0 0 0] /Index [0 2000000000] '
        '/Size 2000000000 /Root 1 0 R /Length 4 >>\nstream\nabcd\n'
        'endstream\nendobj\nstartxref\n$x\n%%EOF\n',
      );
      final bytes = b.takeBytes();
      expect(
        () => CosXrefReader(bytes).parseSection(x),
        throwsA(isA<CosParseException>()),
      );
      final sw = Stopwatch()..start();
      final cos = CosDocument.open(bytes); // falls back to recovery
      expect(cos.catalog['Pages'], isNotNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('over-deep object nesting throws instead of overflowing', () {
      final deep = Uint8List.fromList(latin1.encode('[' * 200000));
      expect(
        () => CosParser(deep).parseObject(),
        throwsA(isA<CosParseException>()),
      );
      final deepDict = Uint8List.fromList(latin1.encode('<</A ' * 100000));
      expect(
        () => CosParser(deepDict).parseObject(),
        throwsA(isA<CosParseException>()),
      );
    });

    test('an object stream /N past its data is clamped', () {
      final pdf = buildPdfObjects([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [] /Count 0 >>',
        PdfStreamBody.text('/Type /ObjStm /N 2000000000 /First 10', '5 0 6 3'),
      ]);
      // break startxref so the open recovers and indexes the object stream.
      final broken = latin1
          .decode(pdf)
          .replaceFirst(RegExp(r'startxref\n\d+'), 'startxref\n999999');
      final sw = Stopwatch()..start();
      final cos = CosDocument.open(Uint8List.fromList(latin1.encode(broken)));
      expect(cos.xrefEntry(5)?.type, CosXrefEntryType.compressed);
      expect(cos.xrefEntry(6)?.type, CosXrefEntryType.compressed);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('encodings and glyph names', () {
    test('tables are complete', () {
      for (final t in [winAnsiEncoding, macRomanEncoding, standardEncoding]) {
        expect(t, hasLength(256));
        expect(t[0x41], 0x41);
        expect(t[0x20], 0x20);
      }
      expect(winAnsiEncoding[0x80], 0x20AC);
      expect(winAnsiEncoding[0xE9], 0xE9);
      expect(macRomanEncoding[0x8E], 0xE9);
      expect(macRomanEncoding[0xDB], 0xA4);
      expect(standardEncoding[0x27], 0x2019);
      expect(standardEncoding[0xAE], 0xFB01);
      // every Mac OS Roman row is 16 wide: 0xFF is the last real entry.
      expect(macRomanEncoding[0xFF], 0x02C7);
    });

    test('glyph names', () {
      expect(glyphNameToText('A'), 'A');
      expect(glyphNameToText('space'), ' ');
      expect(glyphNameToText('hyphen'), '-');
      expect(glyphNameToText('eacute'), 'é');
      expect(glyphNameToText('fi'), 'ﬁ');
      expect(glyphNameToText('f_f_i'), 'ffi');
      expect(glyphNameToText('uni00410042'), 'AB');
      expect(glyphNameToText('u1F600'), '\u{1F600}');
      expect(glyphNameToText('a.alt'), 'a');
      expect(glyphNameToText('.notdef'), isNull);
      expect(glyphNameToText('g123'), isNull);
      expect(glyphNameToText('uniD800'), isNotNull); // lone unit: kept as is
      expect(glyphNameToText('uD800'), isNull);
    });
  });
}
