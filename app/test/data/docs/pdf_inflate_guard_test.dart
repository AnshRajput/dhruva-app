import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:dhruva/data/docs/pdf_inflate_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tiny_pdf.dart';

Uint8List spaces(int n) => Uint8List(n)..fillRange(0, n, 0x20);

void main() {
  group('pdfInflateWithinLimits', () {
    test('accepts a normal compressed text PDF', () {
      final pdf = buildFlatePdf(
        utf8.encode('BT /F1 12 Tf 72 720 Td (Hello flate world) Tj ET'),
      );
      expect(pdfInflateWithinLimits(pdf), isTrue);
    });

    test('accepts a PDF with no streams or with non-zlib streams', () {
      expect(
        pdfInflateWithinLimits(buildTinyPdf(['Plain text page.'])),
        isTrue,
      );
      final junk = latin1.encode(
        '%PDF-1.4\n1 0 obj\n<< >>\nstream\nnot zlib at all\nendstream\n'
        'endobj\n',
      );
      expect(pdfInflateWithinLimits(Uint8List.fromList(junk)), isTrue);
    });

    test('rejects a stream over the per-stream limit', () {
      final pdf = buildFlatePdf(spaces(3 * 1024 * 1024));
      expect(pdfInflateWithinLimits(pdf, maxStream: 1024 * 1024), isFalse);
      expect(pdfInflateWithinLimits(pdf, maxStream: 4 * 1024 * 1024), isTrue);
    });

    test('rejects when streams together pass the total limit', () {
      final one = buildFlatePdf(spaces(1024 * 1024));
      // Two streams in one file: each is under the per-stream cap, together
      // they are over the total cap.
      final twice = Uint8List.fromList([...one, ...one]);
      expect(
        pdfInflateWithinLimits(
          twice,
          maxStream: 1536 * 1024,
          maxTotal: 1536 * 1024,
        ),
        isFalse,
      );
    });

    test('rejects Flate inside Flate (second layer is not followed)', () {
      final inner = ZLibEncoder().convert(spaces(1024));
      expect(pdfInflateWithinLimits(buildFlatePdf(inner)), isFalse);
    });
  });

  group('decompression bomb through the extractor', () {
    // About 100 MB inflated from roughly 100 KB on disk; the unguarded
    // parser needs seconds and hundreds of MB for this.
    test('is refused quickly with a typed error', () {
      final pdf = buildFlatePdf(spaces(100 * 1024 * 1024));
      expect(pdf.length, lessThan(1024 * 1024));
      final sw = Stopwatch()..start();
      try {
        extractDocumentBytes(pdf, 'bomb.pdf');
        fail('expected a DocumentException');
      } on DocumentException catch (e) {
        expect(e.kind, DocumentFailureKind.tooLarge);
      }
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}
