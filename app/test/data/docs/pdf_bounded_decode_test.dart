import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getAdler32;
import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:dhruva/data/docs/pdf_inflate_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import '../../support/tiny_pdf.dart';

const _mb = 1024 * 1024;

Uint8List _filled(int n, int byte) => Uint8List(n)..fillRange(0, n, byte);

CosStream _stream(
  String filter,
  List<int> raw, [
  Map<String, CosObject>? more,
]) {
  return CosStream(
    CosDictionary({'Filter': CosName(filter), ...?more}),
    Uint8List.fromList(raw),
  );
}

/// The reviewer's repro: a zlib header, [stored] non-final stored blocks each
/// holding the literal bytes "endstream", then a raw-deflated [zeros] run and
/// the Adler-32. A scanner that cuts the stream at the first "endstream"
/// sees a tiny, truncated payload; the parser trusts /Length and inflates it
/// all.
Uint8List _endstreamBomb({
  int stored = 9,
  int zeros = 100 * _mb,
  String extra = '',
}) {
  final marker = latin1.encode('endstream');
  final head = BytesBuilder()..add([0x78, 0x01]);
  final plain = BytesBuilder();
  for (var i = 0; i < stored; i++) {
    head.add([0x00, marker.length, 0x00, ~marker.length & 0xff, 0xff]);
    head.add(marker);
    plain.add(marker);
  }
  final zero = Uint8List(zeros);
  head.add(ZLibEncoder(raw: true, level: 9).convert(zero));
  plain.add(zero);
  final adler = getAdler32(plain.takeBytes());
  head.add([adler >> 24 & 0xff, adler >> 16 & 0xff, adler >> 8 & 0xff]);
  head.addByte(adler & 0xff);
  return buildStreamPdf('/Filter /FlateDecode $extra', head.takeBytes());
}

void main() {
  group('the reviewer repro (stored blocks holding "endstream")', () {
    final pdf = _endstreamBomb();

    test('is a small file', () {
      expect(pdf.length, lessThan(200 * 1024));
    });

    test('the guard refuses it', () {
      final sw = Stopwatch()..start();
      expect(pdfSafeToParse(pdf), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('the extractor refuses it as unsafe', () {
      expect(
        () => extractDocumentBytes(pdf, 'x.pdf'),
        throwsA(
          isA<DocumentException>().having(
            (e) => e.kind,
            'kind',
            DocumentFailureKind.unsafe,
          ),
        ),
      );
    });

    test('with the guard bypassed, the decoder itself stops at the cap', () {
      final cos = CosDocument.open(pdf);
      final stream = cos.getObject(5, 0) as CosStream;
      final sw = Stopwatch()..start();
      expect(
        () => cos.decodeStreamData(stream),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
      expect(cos.decodeBudget.tripped, isTrue);
      // Stopped at the per-stream cap, nowhere near the 100 MB payload.
      expect(cos.decodeBudget.usedBytes, lessThanOrEqualTo(16 * _mb));
    });

    test('with the guard bypassed, text extraction latches the cap', () {
      final doc = PdfDocument.open(pdf);
      try {
        PdfTextExtractor.extract(doc, 0);
      } on Object {
        // either rethrown or swallowed inside the library; both are fine.
      }
      expect(doc.cos.decodeBudget.tripped, isTrue);
    });
  });

  group('the guard fails closed', () {
    // The /Length is indirect here, so the guard must cut at `endstream`
    // markers, and the deflate data holds more of them than it will retry.
    test('a stream still incomplete after the retries is refused', () {
      expect(
        pdfSafeToParse(
          _endstreamBomb(stored: 12, zeros: _mb, extra: '/Length 7 0 R'),
        ),
        isFalse,
      );
      // Few enough markers: the retries reach the real end, so it is fine.
      expect(
        pdfSafeToParse(
          _endstreamBomb(stored: 3, zeros: _mb, extra: '/Length 7 0 R'),
        ),
        isTrue,
      );
    });

    test('a direct /Length that "endstream" follows is honoured', () {
      // Same 12 markers, but /Length covers the whole stream in one pass.
      expect(pdfSafeToParse(_endstreamBomb(stored: 12, zeros: _mb)), isTrue);
    });

    test('a normal compressed PDF is still accepted', () {
      final pdf = buildFlatePdf(
        utf8.encode('BT /F1 12 Tf 72 720 Td (Hello flate world) Tj ET'),
      );
      expect(pdfSafeToParse(pdf), isTrue);
    });
  });

  group('every filter stops at the cap', () {
    test('Flate (stream cap)', () {
      final z = ZLibEncoder(level: 9).convert(_filled(20 * _mb, 0x20));
      expect(
        () => decodeStream(_stream('FlateDecode', z)),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
      // Under the cap it decodes fine.
      final ok = ZLibEncoder().convert(_filled(2 * _mb, 0x20));
      expect(decodeStream(_stream('FlateDecode', ok)).length, 2 * _mb);
    });

    test('Flate tolerates bytes after the stream', () {
      final z = ZLibEncoder().convert(utf8.encode('hello'));
      final out = decodeStream(_stream('FlateDecode', [...z, 13, 10]));
      expect(utf8.decode(out), 'hello');
    });

    test('RunLength', () {
      final pairs = Uint8List(2 * 150000);
      for (var i = 0; i < pairs.length; i += 2) {
        pairs[i] = 129; // repeat the next byte 128 times
      }
      expect(
        () => decodeStream(_stream('RunLengthDecode', pairs)),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('ASCII85 (the z shorthand)', () {
      expect(
        () => decodeStream(_stream('ASCII85Decode', _filled(5 * _mb, 0x7a))),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('ASCIIHex', () {
      final ok = decodeStream(
        _stream('ASCIIHexDecode', latin1.encode('4142>')),
      );
      expect(ok, [0x41, 0x42]);
      expect(
        () => decodeStream(
          _stream('ASCIIHexDecode', _filled(40 * _mb, 0x30)),
          budget: DecodeBudget(maxStreamBytes: 4 * _mb),
        ),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('LZW', () {
      // 9-bit codes: clear, then code 65 over and over = 1 byte per 9 bits.
      // Few bytes in, but with a tiny cap the output is refused early.
      final bits = StringBuffer('100000000'); // clear (256)
      for (var i = 0; i < 200; i++) {
        bits.write('001000001'); // 65
      }
      bits.write('100000001'); // EOD (257)
      final s = bits.toString().padRight((bits.length + 7) ~/ 8 * 8, '0');
      final bytes = Uint8List(s.length ~/ 8);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = int.parse(s.substring(i * 8, i * 8 + 8), radix: 2);
      }
      expect(decodeStream(_stream('LZWDecode', bytes)).length, 200);
      expect(
        () => decodeStream(
          _stream('LZWDecode', bytes),
          budget: DecodeBudget(maxStreamBytes: 100),
        ),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('CCITT geometry', () {
      expect(
        () => decodeStream(
          _stream('CCITTFaxDecode', _filled(16, 0), {
            'DecodeParms': CosDictionary({
              'K': const CosInteger(-1),
              'Columns': const CosInteger(1000000),
              'Rows': const CosInteger(1000000),
            }),
          }),
        ),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('predictor with a hostile /Columns does not allocate it', () {
      final z = ZLibEncoder().convert(_filled(64, 0));
      for (final columns in [2000000000, 1 << 40]) {
        expect(
          () => decodeStream(
            _stream('FlateDecode', z, {
              'DecodeParms': CosDictionary({
                'Predictor': const CosInteger(12),
                'Columns': CosInteger(columns),
              }),
            }),
          ),
          throwsA(
            anyOf(isA<PdfDecodeLimitExceeded>(), isA<CosParseException>()),
          ),
        );
      }
    });
  });

  group('per-document cap', () {
    test('streams that are each fine but together too big are refused', () {
      final z = ZLibEncoder().convert(_filled(1 * _mb, 0x20));
      final budget = DecodeBudget(
        maxStreamBytes: 2 * _mb,
        maxTotalBytes: 3 * _mb ~/ 2,
      );
      decodeStream(_stream('FlateDecode', z), budget: budget);
      expect(budget.tripped, isFalse);
      expect(
        () => decodeStream(_stream('FlateDecode', z), budget: budget),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
      expect(budget.tripped, isTrue);
    });

    // Nine pages, each a 15 MB (under the 16 MB stream cap) content stream:
    // 135 MB together, over the 128 MB document cap. The guard's own limits
    // (64 MB / 200 MB) let it through, so the decoder is what refuses.
    test('a real document over 128 MB total is refused as unsafe', () {
      final z = ZLibEncoder(level: 9).convert(_filled(15 * _mb, 0x20));
      final pdf = _multiPagePdf(9, z);
      expect(pdfSafeToParse(pdf), isTrue, reason: 'guard alone lets it pass');
      expect(
        () => extractDocumentBytes(pdf, 'big.pdf'),
        throwsA(
          isA<DocumentException>().having(
            (e) => e.kind,
            'kind',
            DocumentFailureKind.unsafe,
          ),
        ),
      );
    });

    test('eight such pages (120 MB) stay under the cap', () {
      final z = ZLibEncoder(level: 9).convert(_filled(15 * _mb, 0x20));
      final doc = PdfDocument.open(_multiPagePdf(8, z));
      for (var i = 0; i < 8; i++) {
        PdfTextExtractor.extract(doc, i);
      }
      expect(doc.cos.decodeBudget.tripped, isFalse);
    });
  });

  group('page cap', () {
    test(
      'only the first $maxPdfPages pages are read',
      () {
        final pages = [
          for (var i = 0; i < maxPdfPages + 5; i++)
            'Page number $i has enough text.',
        ];
        final doc = extractDocumentBytes(buildTinyPdf(pages), 'long.pdf');
        expect(doc.pageCount, maxPdfPages);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

/// A document of [pages] pages whose content streams are all the same
/// FlateDecode payload [z].
Uint8List _multiPagePdf(int pages, List<int> z) {
  final b = BytesBuilder();
  final offs = <int>[];
  void w(String s) => b.add(latin1.encode(s));
  void obj(String body) {
    offs.add(b.length);
    w('${offs.length} 0 obj\n$body\nendobj\n');
  }

  w('%PDF-1.4\n');
  final kids = [for (var i = 0; i < pages; i++) '${4 + i * 2} 0 R'].join(' ');
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Kids [$kids] /Count $pages >>');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pages; i++) {
    obj(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>',
    );
    offs.add(b.length);
    w(
      '${offs.length} 0 obj\n<< /Length ${z.length} /Filter /FlateDecode >>\n'
      'stream\n',
    );
    b.add(z);
    w('\nendstream\nendobj\n');
  }
  final x = b.length;
  w('xref\n0 ${offs.length + 1}\n0000000000 65535 f \n');
  for (final o in offs) {
    w('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  w(
    'trailer\n<< /Size ${offs.length + 1} /Root 1 0 R >>\nstartxref\n$x\n%%EOF\n',
  );
  return b.takeBytes();
}
