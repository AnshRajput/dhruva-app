import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:dhruva/data/docs/pdf_inflate_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tiny_pdf.dart';

Uint8List spaces(int n) => Uint8List(n)..fillRange(0, n, 0x20);

final _text = utf8.encode('BT /F1 12 Tf 72 720 Td (Hello flate world) Tj ET');

/// A stream whose payload is ordinary text but whose dictionary claims
/// [dict]; the guard must decide from the dictionary alone.
Uint8List withDict(String dict, [List<int>? payload]) =>
    buildStreamPdf(dict, payload ?? latin1.encode('~>'));

const _image = '/Type /XObject /Subtype /Image /Width 1 /Height 1 ';

void main() {
  group('flate streams', () {
    test('accepts a normal compressed text PDF', () {
      expect(pdfSafeToParse(buildFlatePdf(_text)), isTrue);
    });

    test('accepts one Flate in every spelling', () {
      final z = ZLibEncoder().convert(_text);
      for (final d in [
        '/Filter /FlateDecode',
        '/Filter /Fl',
        '/Filter [/FlateDecode]',
        '/Filter /Flate#44ecode',
        '/Filter [ /FlateDecode ] /DecodeParms [ << /Predictor 12 '
            '/Columns 5 >> ]',
        '/Filter /FlateDecode /DecodeParms << /Predictor 15 /Columns 4 >>',
        '/Filter /FlateDecode /DecodeParms null',
      ]) {
        expect(pdfSafeToParse(withDict(d, z)), isTrue, reason: d);
      }
    });

    test('accepts a PDF with no filters or with non-zlib Flate streams', () {
      expect(pdfSafeToParse(buildTinyPdf(['Plain text page.'])), isTrue);
      expect(
        pdfSafeToParse(withDict('/Filter /FlateDecode', latin1.encode('xx'))),
        isTrue,
      );
    });

    test('rejects a stream over the per-stream limit', () {
      final pdf = buildFlatePdf(spaces(3 * 1024 * 1024));
      expect(pdfSafeToParse(pdf, maxStream: 1024 * 1024), isFalse);
      expect(pdfSafeToParse(pdf, maxStream: 4 * 1024 * 1024), isTrue);
    });

    test('rejects when streams together pass the total limit', () {
      final one = buildFlatePdf(spaces(1024 * 1024));
      // Two streams in one file: each is under the per-stream cap, together
      // they are over the total cap.
      final twice = Uint8List.fromList([...one, ...one]);
      expect(
        pdfSafeToParse(twice, maxStream: 1536 * 1024, maxTotal: 1536 * 1024),
        isFalse,
      );
    });

    test('rejects Flate inside Flate (second layer is not followed)', () {
      final inner = ZLibEncoder().convert(spaces(1024));
      expect(pdfSafeToParse(buildFlatePdf(inner)), isFalse);
    });

    test('rejects a predictor that would allocate a giant row buffer', () {
      final z = ZLibEncoder().convert(_text);
      expect(
        pdfSafeToParse(
          withDict(
            '/Filter /FlateDecode /DecodeParms << /Predictor 12 '
            '/Columns 2000000000 >>',
            z,
          ),
        ),
        isFalse,
      );
    });
  });

  group('filter chains and exotic filters are refused', () {
    final z = ZLibEncoder().convert(_text);
    for (final entry in {
      'ASCII85 + Flate': '/Filter [/ASCII85Decode /FlateDecode]',
      'A85 + Fl': '/Filter [/A85 /Fl]',
      'ASCIIHex + Flate': '/Filter [/ASCIIHexDecode /FlateDecode]',
      'Flate + ASCIIHex': '/Filter [/FlateDecode /ASCIIHexDecode]',
      'Flate + Flate': '/Filter [/FlateDecode /FlateDecode]',
      'RunLength alone': '/Filter /RunLengthDecode',
      'RunLength chain': '/Filter [/RunLengthDecode /FlateDecode]',
      'LZW alone': '/Filter /LZWDecode',
      'LZW chain': '/Filter [/LZWDecode /FlateDecode]',
      'escaped name hides ASCII85': '/Filter [/ASCII#38#35Decode /Fl]',
      'ASCII85 alone': '/Filter /ASCII85Decode',
      'image filter on a non-image': '/Filter /DCTDecode',
      'DCT after Flate on an image': '$_image/Filter [/FlateDecode /DCTDecode]',
    }.entries) {
      test(entry.key, () {
        expect(pdfSafeToParse(withDict(entry.value, z)), isFalse);
      });
    }

    test('an object stream or xref stream gets no exemption', () {
      expect(
        pdfSafeToParse(
          withDict(
            '/Type /ObjStm /N 1 /First 4 '
            '/Filter [/ASCIIHexDecode /FlateDecode]',
            z,
          ),
        ),
        isFalse,
      );
      expect(
        pdfSafeToParse(
          withDict(
            '/Type /XRef /W [1 2 1] /Size 6 /Filter [/LZWDecode /FlateDecode]',
            z,
          ),
        ),
        isFalse,
      );
      // ...and a plain Flate one is fine.
      expect(
        pdfSafeToParse(
          withDict('/Type /ObjStm /N 1 /First 4 /Filter /FlateDecode', z),
        ),
        isTrue,
      );
    });
  });

  group('malformed or indirect /Filter is refused', () {
    final z = ZLibEncoder().convert(_text);
    for (final entry in {
      'integer': '/Filter 5',
      'string': '/Filter (FlateDecode)',
      'dictionary': '/Filter << /A /FlateDecode >>',
      'indirect reference': '/Filter 7 0 R',
      'indirect name in array': '/Filter [7 0 R]',
      'non-name in array': '/Filter [/FlateDecode 3]',
      'indirect DecodeParms': '/Filter /FlateDecode /DecodeParms 7 0 R',
      'indirect DecodeParms entry': '/Filter /FlateDecode /DecodeParms [7 0 R]',
      'indirect DP': '/Filter /FlateDecode /DP 7 0 R',
      'non-dictionary DecodeParms': '/Filter /FlateDecode /DecodeParms 3',
    }.entries) {
      test(entry.key, () {
        expect(pdfSafeToParse(withDict(entry.value, z)), isFalse);
      });
    }
  });

  group('image streams', () {
    final junk = Uint8List.fromList(List.generate(64, (i) => i * 7 & 0xff));

    test('DCT/JPX/JBIG2 images are accepted and never decoded', () {
      for (final f in ['DCTDecode', 'JPXDecode', 'JBIG2Decode']) {
        expect(
          pdfSafeToParse(withDict('$_image/Filter /$f', junk)),
          isTrue,
          reason: f,
        );
        expect(
          pdfSafeToParse(withDict('$_image/Filter [/$f]', junk)),
          isTrue,
          reason: '[$f]',
        );
      }
    });

    test('an image stream next to normal objects is accepted', () {
      final pages = buildTinyPdf([
        'This page has a real text layer that can be extracted fine.',
      ]);
      final image = latin1.encode(
        '1 0 obj\n<< $_image/Filter /DCTDecode /Length 64 >>\nstream\n',
      );
      final out = Uint8List.fromList([...image, ...junk, ...pages]);
      expect(pdfSafeToParse(out), isTrue);
    });

    test('CCITT needs an explicit, bounded Rows x Columns', () {
      expect(
        pdfSafeToParse(
          withDict(
            '$_image/Filter /CCITTFaxDecode '
            '/DecodeParms << /K -1 /Columns 1700 /Rows 2200 >>',
            junk,
          ),
        ),
        isTrue,
      );
      // No /Rows: the decoder would run until the data ends.
      expect(
        pdfSafeToParse(
          withDict(
            '$_image/Filter /CCITTFaxDecode /DecodeParms << /K -1 >>',
            junk,
          ),
        ),
        isFalse,
      );
      // A declared size far past the cap.
      expect(
        pdfSafeToParse(
          withDict(
            '$_image/Filter /CCITTFaxDecode '
            '/DecodeParms << /K -1 /Columns 1000000 /Rows 1000000 >>',
            junk,
          ),
        ),
        isFalse,
      );
      expect(
        pdfSafeToParse(withDict('/Filter /CCITTFaxDecode', junk)),
        isFalse,
      );
    });
  });

  group('streams hidden from a plain scan', () {
    final hidden = latin1.encode(
      '<< /Filter [/ASCII85Decode /FlateDecode] /Length 2 >>\n'
      'stream\n~>\nendstream\n',
    );

    test('a stream inside a raw (unfiltered) object stream', () {
      expect(pdfSafeToParse(withDict('/Type /ObjStm /N 1', hidden)), isFalse);
    });

    test('a stream inside an inflated object stream', () {
      final z = ZLibEncoder().convert(hidden);
      expect(
        pdfSafeToParse(withDict('/Type /ObjStm /Filter /FlateDecode', z)),
        isFalse,
      );
    });

    test('a comment between the dictionary and stream does not hide it', () {
      final sneaky = latin1.encode(
        '<< /Filter /LZWDecode >> % c\nstream\nx\nendstream\n',
      );
      final z = ZLibEncoder().convert(sneaky);
      expect(
        pdfSafeToParse(withDict('/Type /ObjStm /Filter /FlateDecode', z)),
        isFalse,
      );
      expect(pdfSafeToParse(withDict('/Type /ObjStm', sneaky)), isFalse);
    });

    test('a stream nested as another dictionary value', () {
      expect(
        pdfSafeToParse(
          withDict(
            '/Inner << /Filter /LZWDecode >>\nstream\nx\nendstream\n',
            latin1.encode('x'),
          ),
        ),
        isFalse,
      );
    });

    test('an unclosed-dictionary flood is refused, not quadratic', () {
      final flood = Uint8List.fromList(
        latin1.encode('<< /A (unclosed ' * 200000),
      );
      final sw = Stopwatch()..start();
      expect(pdfSafeToParse(flood), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('a deeply nested dictionary is refused', () {
      final deep = latin1.encode('${'<< /A ' * 100}1${' >>' * 100}');
      expect(pdfSafeToParse(Uint8List.fromList(deep)), isFalse);
    });
  });

  group('through the extractor', () {
    void expectUnsafe(Uint8List pdf) {
      try {
        extractDocumentBytes(pdf, 'x.pdf');
        fail('expected a DocumentException');
      } on DocumentException catch (e) {
        expect(e.kind, DocumentFailureKind.unsafe);
        expect(e.message, contains("can't read this PDF safely"));
      }
    }

    test('a filter chain is refused with a plain-language error', () {
      expectUnsafe(withDict('/Filter [/ASCII85Decode /FlateDecode]'));
      expectUnsafe(withDict('/Filter [/ASCIIHexDecode /FlateDecode]'));
      expectUnsafe(withDict('/Filter /RunLengthDecode'));
      expectUnsafe(withDict('/Filter /LZWDecode'));
    });

    // About 100 MB inflated from roughly 100 KB on disk; the unguarded
    // parser needs seconds and hundreds of MB for this.
    test('a decompression bomb is refused quickly', () {
      final pdf = buildFlatePdf(spaces(100 * 1024 * 1024));
      expect(pdf.length, lessThan(1024 * 1024));
      final sw = Stopwatch()..start();
      expectUnsafe(pdf);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('a normal Flate PDF is still read', () {
      final pdf = buildFlatePdf(
        utf8.encode(
          'BT /F1 12 Tf 72 720 Td '
          '(A perfectly ordinary compressed page with enough words.) Tj ET',
        ),
      );
      final doc = extractDocumentBytes(pdf, 'ok.pdf');
      expect(doc.chunks.single.text, contains('ordinary compressed page'));
    });
  });
}
