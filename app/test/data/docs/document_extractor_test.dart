import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tiny_pdf.dart';

Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

void expectFailure(
  void Function() body,
  DocumentFailureKind kind, [
  Pattern? message,
]) {
  try {
    body();
    fail('expected a DocumentException($kind)');
  } on DocumentException catch (e) {
    expect(e.kind, kind);
    if (message != null) expect(e.message, contains(message));
  }
}

void main() {
  group('text files', () {
    test('TXT is read as one page-less document', () {
      final doc = extractDocumentBytes(
        utf8Bytes('Hello there.\n\nSecond paragraph about warranty.'),
        'notes.txt',
      );
      expect(doc.mime, 'text/plain');
      expect(doc.pageCount, 0);
      expect(doc.paged, isFalse);
      expect(doc.charCount, greaterThan(20));
      expect(doc.chunks, isNotEmpty);
      expect(doc.chunks.first.page, 1);
    });

    test('MD gets the markdown mime type', () {
      final doc = extractDocumentBytes(utf8Bytes('# Title\n\nBody'), 'a.md');
      expect(doc.mime, 'text/markdown');
    });

    test('bad UTF-8 is decoded leniently, not rejected', () {
      final bytes = Uint8List.fromList([
        ...utf8.encode('caf'),
        0xE9, // lone latin-1 byte: invalid UTF-8
        ...utf8.encode(' au lait'),
      ]);
      final doc = extractDocumentBytes(bytes, 'menu.txt');
      expect(doc.chunks.single.text, contains('au lait'));
    });

    test('a BOM is stripped', () {
      final doc = extractDocumentBytes(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('hello')]),
        'a.txt',
      );
      expect(doc.chunks.single.text, 'hello');
    });

    test('long text becomes several parts, each with chunks', () {
      final text = List.generate(400, (i) => 'Line $i of the file.').join('\n');
      final doc = extractDocumentBytes(utf8Bytes(text), 'big.txt');
      expect(doc.chunks.map((c) => c.page).toSet().length, greaterThan(1));
    });

    test('an empty file is rejected plainly', () {
      expectFailure(
        () => extractDocumentBytes(utf8Bytes('  \n '), 'e.txt'),
        DocumentFailureKind.empty,
      );
    });

    test('over 400k characters is rejected', () {
      final text = ('word ' * 90000); // 450k chars
      expectFailure(
        () => extractDocumentBytes(utf8Bytes(text), 'huge.txt'),
        DocumentFailureKind.tooLong,
        '400,000',
      );
    });
  });

  group('PDF', () {
    test('extracts text per page and counts pages', () {
      final doc = extractDocumentBytes(
        buildTinyPdf([
          'The warranty lasts two years from the purchase date.',
          'Shipping takes seven business days to most countries.',
        ]),
        'terms.pdf',
      );
      expect(doc.mime, 'application/pdf');
      expect(doc.pageCount, 2);
      expect(doc.paged, isTrue);
      final p1 = doc.chunks.where((c) => c.page == 1).map((c) => c.text);
      final p2 = doc.chunks.where((c) => c.page == 2).map((c) => c.text);
      expect(p1.join(' '), contains('warranty'));
      expect(p2.join(' '), contains('Shipping'));
      expect(p1.join(' '), isNot(contains('Shipping')));
    });

    test('a PDF is recognised by its bytes even without an extension', () {
      final doc = extractDocumentBytes(
        buildTinyPdf([
          'Some readable text that is comfortably long enough to count here.',
        ]),
        'download',
      );
      expect(doc.pageCount, 1);
    });

    test('an image-only (scanned) PDF says there is no text', () {
      expectFailure(
        () => extractDocumentBytes(buildTinyPdf(['', '']), 'scan.pdf'),
        DocumentFailureKind.noText,
        'no selectable text',
      );
    });

    test('a damaged PDF is reported as unreadable', () {
      expectFailure(
        () => extractDocumentBytes(utf8Bytes('%PDF-1.4 garbage'), 'bad.pdf'),
        DocumentFailureKind.unreadable,
      );
    });
  });

  group('limits and types', () {
    test('an unsupported type is rejected', () {
      expectFailure(
        () => extractDocumentBytes(utf8Bytes('x'), 'photo.png'),
        DocumentFailureKind.unsupported,
      );
    });

    test('over 20 MB is rejected before any parsing', () {
      expectFailure(
        () => extractDocumentBytes(Uint8List(maxDocumentBytes + 1), 'big.pdf'),
        DocumentFailureKind.tooLarge,
        '20 MB',
      );
    });
  });

  group('extractDocumentFile (isolate)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('doc_extract_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('reads and chunks a file off the calling isolate', () async {
      final f = File('${tmp.path}/a.pdf')
        ..writeAsBytesSync(
          buildTinyPdf([
            'Isolate extraction works fine on this page of text content.',
          ]),
        );
      final doc = await extractDocumentFile(f.path, 'a.pdf');
      expect(doc.pageCount, 1);
      expect(doc.chunks.single.text, contains('Isolate'));
    });

    test('failures cross the isolate as typed exceptions', () async {
      final f = File('${tmp.path}/s.pdf')..writeAsBytesSync(buildTinyPdf(['']));
      await expectLater(
        extractDocumentFile(f.path, 's.pdf'),
        throwsA(
          isA<DocumentException>().having(
            (e) => e.kind,
            'kind',
            DocumentFailureKind.noText,
          ),
        ),
      );
    });

    test('a file over 20 MB is refused from its size alone', () async {
      final f = File('${tmp.path}/huge.txt');
      final raf = f.openSync(mode: FileMode.write)
        ..truncateSync(maxDocumentBytes + 1);
      raf.closeSync();
      await expectLater(
        extractDocumentFile(f.path, 'huge.txt'),
        throwsA(
          isA<DocumentException>().having(
            (e) => e.kind,
            'kind',
            DocumentFailureKind.tooLarge,
          ),
        ),
      );
    });
  });
}
