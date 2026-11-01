// Memory regression tests for the vendored decoders (third_party/pdf_cos).
//
// The output byte cap (16 MB per stage) is not enough on its own: a stage
// that allocates one object per run / code / row costs 30-40x the bytes it
// produces (the round-4 review measured ~450-650 MB for a capped RunLength
// or LZW stream). So every filter must write into ONE growing buffer.
//
// METHOD. Each test builds a worst-case input that decodes to (about) the
// full 16 MB stage cap, runs the filter, and checks:
//
//  1. DETERMINISTIC (asserted, not flaky): [DecodeBufferStats], a test hook
//     in the decoder's shared output buffer, counts every backing array a
//     filter allocates and the most bytes live at once. A filter that
//     regresses to per-run objects either bypasses the buffer (the output is
//     then no longer one array) or makes thousands of allocations; both
//     fail here. Peak live bytes must stay under 3x the cap.
//  2. REAL MEMORY (asserted loosely, printed always): the growth of
//     ProcessInfo.maxRss (the process high-water mark) across the decode.
//     maxRss only ever grows, so inside a shared test process it can
//     under-report when an earlier test already set a higher peak; run one
//     test alone (`--plain-name`) for a clean number. It is asserted below
//     3x the cap and printed as `MEM <name> ...`.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:dhruva/data/docs/pdf_inflate_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';

import '../../support/tiny_pdf.dart';

const _mb = 1024 * 1024;
const _cap = DecodeBudget.defaultMaxStreamBytes; // 16 MB

/// Runs [decode], prints and returns its memory numbers, and asserts the
/// bounds described at the top of the file. [usesBuffer] is false for
/// filters whose output is produced inside a library (archive's inflate).
Uint8List _measured(
  String name,
  Uint8List Function() decode, {
  bool usesBuffer = true,
  int expectedLength = _cap,
}) {
  DecodeBufferStats.reset();
  final before = ProcessInfo.maxRss;
  final resident = ProcessInfo.currentRss;
  final out = decode();
  final rssDelta = ProcessInfo.maxRss - before;
  // ignore: avoid_print
  print(
    'MEM $name: out=${out.length ~/ _mb} MB '
    'maxRss+=${(rssDelta / _mb).toStringAsFixed(1)} MB '
    'peakOverResident=${((ProcessInfo.maxRss - resident) / _mb).toStringAsFixed(1)} MB '
    'bufferAllocs=${DecodeBufferStats.allocations} '
    'bufferPeakLive=${(DecodeBufferStats.peakLiveBytes / _mb).toStringAsFixed(1)} MB',
  );
  expect(out.length, expectedLength);
  // RSS has a fixed noise floor (allocator pages, zlib state) that no longer
  // scales with the 4 MB stage cap, so 3x the cap alone (12 MB) is below it.
  // The blow-ups this guards against were hundreds of MB.
  const rssFloor = 32 * _mb;
  expect(
    rssDelta,
    lessThan(3 * _cap > rssFloor ? 3 * _cap : rssFloor),
    reason: '$name real memory growth',
  );
  if (usesBuffer) {
    expect(
      DecodeBufferStats.allocations,
      inInclusiveRange(1, 40),
      reason: '$name must write into one growing buffer',
    );
    expect(
      DecodeBufferStats.peakLiveBytes,
      lessThan(3 * _cap),
      reason: '$name peak live bytes',
    );
  }
  return out;
}

/// An LZW encoder that emits one 1-byte literal per code (the worst case:
/// every code costs a code's worth of dictionary work and one byte of
/// output) and resets the dictionary before it fills, mirroring the
/// decoder's code-width rules (EarlyChange 1).
Uint8List _lzwLiterals(int count) {
  final out = BytesBuilder(copy: false);
  var acc = 0, bits = 0, width = 9, next = 258;
  var havePrevious = false;
  void emit(int code) {
    acc = (acc << width) | code;
    bits += width;
    while (bits >= 8) {
      out.addByte((acc >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
    acc &= (1 << bits) - 1;
  }

  void clear() {
    emit(256);
    width = 9;
    next = 258;
    havePrevious = false;
  }

  clear();
  for (var i = 0; i < count; i++) {
    emit(i & 0xFF);
    if (havePrevious && next <= 4095) next++;
    havePrevious = true;
    if (width < 12 && next + 1 > (1 << width)) width++;
    if (next >= 4000) clear();
  }
  emit(257);
  if (bits > 0) out.addByte((acc << (8 - bits)) & 0xFF);
  return out.takeBytes();
}

CosDictionary _params(Map<String, int> ints) =>
    CosDictionary({for (final e in ints.entries) e.key: CosInteger(e.value)});

void main() {
  // --- correctness: the rewritten decoders must still decode -------------
  group('rewritten decoders still decode', () {
    Uint8List run(CosFilter f, List<int> data, [CosDictionary? p]) =>
        f.decode(Uint8List.fromList(data), p, DecodeBudget());

    test('LZW: the ISO 32000 spec example', () {
      expect(
        run(const LzwFilter(), [
          0x80,
          0x0B,
          0x60,
          0x50,
          0x22,
          0x0C,
          0x0C,
          0x85,
          0x01,
        ]),
        [45, 45, 45, 45, 45, 65, 45, 45, 45, 66],
      );
    });

    test(
      'LZW: round-trips a 1-byte-per-code stream across dictionary resets',
      () {
        final out = run(const LzwFilter(), _lzwLiterals(10000));
        expect(out.length, 10000);
        for (var i = 0; i < out.length; i++) {
          if (out[i] != (i & 0xFF)) fail('byte $i is ${out[i]}');
        }
      },
    );

    test('LZW: a code that was never defined is rejected', () {
      // CLEAR, then code 300 (undefined), 9 bits each.
      final bits = (256 << 9 | 300) << 6;
      expect(
        () =>
            run(const LzwFilter(), [bits >> 16, bits >> 8 & 0xFF, bits & 0xFF]),
        throwsA(isA<CosParseException>()),
      );
    });

    test('RunLength: literals, runs, EOD', () {
      expect(run(const RunLengthFilter(), [2, 1, 2, 3, 254, 9, 128, 7, 7]), [
        1,
        2,
        3,
        9,
        9,
        9,
      ]);
    });

    test('ASCII85 and ASCIIHex', () {
      expect(
        utf8.decode(
          run(const Ascii85Filter(), latin1.encode('87cURD]i,"Ebo80~>')),
        ),
        'Hello World!',
      );
      expect(run(const Ascii85Filter(), latin1.encode('z~>')), [0, 0, 0, 0]);
      expect(run(const AsciiHexFilter(), latin1.encode('48 65 6c6C 6f7>')), [
        0x48,
        0x65,
        0x6c,
        0x6c,
        0x6f,
        0x70,
      ]);
    });

    test('CCITT G4: declared rows, short data pads with white', () {
      // 0xFF = eight V0 codes = eight all-white rows; ask for 10.
      final out = run(const CcittFaxFilter(), [
        0xFF,
      ], _params({'K': -1, 'Columns': 16, 'Rows': 10}));
      expect(out.length, 20);
      expect(out.every((b) => b == 0xFF), isTrue);
    });

    test('CCITT G4: no /Rows decodes until the data runs out', () {
      final out = run(const CcittFaxFilter(), [
        0xFF,
        0xFF,
      ], _params({'K': -1, 'Columns': 16}));
      expect(out.length, 32);
    });
  });

  // --- memory: worst case at the stage cap, every filter -----------------
  group('worst case at the 16 MB stage cap stays under 3x', () {
    test('FlateDecode (zeros)', () {
      final z = ZLibEncoder(level: 9).convert(Uint8List(_cap));
      _measured(
        'Flate',
        () => const FlateFilter().decode(
          Uint8List.fromList(z),
          null,
          DecodeBudget(),
        ),
        usesBuffer: false,
      );
    });

    test('FlateDecode + PNG predictor (rows of 4095 bytes)', () {
      const columns = 4095;
      final rows = _cap ~/ (columns + 1);
      final z = ZLibEncoder(level: 9).convert(Uint8List(rows * (columns + 1)));
      _measured(
        'Flate+PNG predictor',
        () => const FlateFilter().decode(
          Uint8List.fromList(z),
          _params({'Predictor': 15, 'Columns': columns}),
          DecodeBudget(),
        ),
        usesBuffer: false,
        expectedLength: rows * columns,
      );
    });

    test('FlateDecode + TIFF predictor (in place)', () {
      final z = ZLibEncoder(level: 9).convert(Uint8List(_cap));
      _measured(
        'Flate+TIFF predictor',
        () => const FlateFilter().decode(
          Uint8List.fromList(z),
          _params({'Predictor': 2, 'Columns': 4096}),
          DecodeBudget(),
        ),
        usesBuffer: false,
      );
    });

    test('RunLengthDecode (16M one-byte literals)', () {
      final data = Uint8List(2 * _cap);
      for (var i = 0; i < data.length; i += 2) {
        data[i + 1] = 0x41; // [length 0, byte]: a 1-byte literal each
      }
      final out = _measured(
        'RunLength 1-byte literals',
        () => const RunLengthFilter().decode(data, null, DecodeBudget()),
      );
      expect(out.first, 0x41);
      expect(out.last, 0x41);
    });

    test('RunLengthDecode (8M two-byte runs)', () {
      final data = Uint8List(_cap);
      for (var i = 0; i < data.length; i += 2) {
        data[i] = 255; // repeat the next byte 2 times
        data[i + 1] = 0x42;
      }
      _measured(
        'RunLength 2-byte runs',
        () => const RunLengthFilter().decode(data, null, DecodeBudget()),
      );
    });

    test('LZWDecode (16M one-byte codes)', () {
      final data = _lzwLiterals(_cap);
      final out = _measured(
        'LZW 1-byte codes',
        () => const LzwFilter().decode(data, null, DecodeBudget()),
      );
      expect(out[255], 255);
      expect(out[_cap - 1], (_cap - 1) & 0xFF);
    });

    test('ASCII85Decode (5-char groups)', () {
      final data = Uint8List(_cap ~/ 4 * 5)..fillRange(0, _cap ~/ 4 * 5, 0x21);
      _measured(
        'ASCII85 groups',
        () => const Ascii85Filter().decode(data, null, DecodeBudget()),
      );
    });

    test('ASCII85Decode (z runs)', () {
      final data = Uint8List(_cap ~/ 4)..fillRange(0, _cap ~/ 4, 0x7A);
      _measured(
        'ASCII85 z',
        () => const Ascii85Filter().decode(data, null, DecodeBudget()),
      );
    });

    test('ASCIIHexDecode', () {
      final data = Uint8List(2 * _cap)..fillRange(0, 2 * _cap, 0x30);
      _measured(
        'ASCIIHex',
        () => const AsciiHexFilter().decode(data, null, DecodeBudget()),
      );
    });

    test('CCITTFaxDecode (declared /Rows)', () {
      const columns = 1024; // 128-byte rows
      final rows = _cap ~/ (columns ~/ 8);
      final data = Uint8List(rows ~/ 8)..fillRange(0, rows ~/ 8, 0xFF);
      _measured(
        'CCITT Rows',
        () => const CcittFaxFilter().decode(
          data,
          _params({'K': -1, 'Columns': columns, 'Rows': rows}),
          DecodeBudget(),
        ),
        usesBuffer: false, // one preallocated array, charged up front
      );
    });

    test('CCITTFaxDecode (no /Rows, grows row by row)', () {
      const columns = 1024;
      final rows = _cap ~/ (columns ~/ 8);
      final data = Uint8List(rows ~/ 8)..fillRange(0, rows ~/ 8, 0xFF);
      _measured(
        'CCITT no Rows',
        () => const CcittFaxFilter().decode(
          data,
          _params({'K': -1, 'Columns': columns}),
          DecodeBudget(),
        ),
      );
    });

    test('CCITT: a row of zero-length runs cannot grow without bound', () {
      // Group 3 1-D: white run of length 0 is 00110101, forever. Each code
      // adds a transition without advancing; the row must give up.
      final data = Uint8List(1 * _mb);
      for (var i = 0; i < data.length; i += 1) {
        data[i] = 0x35; // 00110101
      }
      final sw = Stopwatch()..start();
      final out = const CcittFaxFilter().decode(
        data,
        _params({'K': 0, 'Columns': 64, 'Rows': 4}),
        DecodeBudget(),
      );
      expect(out.length, 4 * 8);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });

  // --- the budget is shared, not per decode site --------------------------
  group('one budget per document', () {
    // A cross-reference-stream PDF (Flate-compressed xref rows).
    Uint8List xrefStreamPdf() {
      final b = BytesBuilder();
      final offs = <int>[];
      void w(String s) => b.add(latin1.encode(s));
      w('%PDF-1.5\n');
      for (final o in [
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [] /Count 0 >>',
      ]) {
        offs.add(b.length);
        w('${offs.length} 0 obj\n$o\nendobj\n');
      }
      final xrefAt = b.length;
      final rows = BytesBuilder();
      void row(int type, int a, int c) => rows.add([type, a >> 8, a & 0xFF, c]);
      row(0, 0, 255);
      for (final o in offs) {
        row(1, o, 0);
      }
      row(1, xrefAt, 0);
      final z = ZLibEncoder().convert(rows.takeBytes());
      w(
        '3 0 obj\n<< /Type /XRef /Size 4 /W [1 2 1] /Root 1 0 R '
        '/Filter /FlateDecode /Length ${z.length} >>\nstream\n',
      );
      b.add(z);
      w('\nendstream\nendobj\nstartxref\n$xrefAt\n%%EOF\n');
      return b.takeBytes();
    }

    test('the xref stream decode is charged to the document budget', () {
      final cos = CosDocument.open(xrefStreamPdf());
      expect(cos.startXref, greaterThan(0), reason: 'opened via the xref');
      // 4 rows x 4 bytes: the document's budget saw the xref stream.
      expect(cos.decodeBudget.usedBytes, 16);
    });

    test('a reader given a budget draws from it', () {
      final pdf = xrefStreamPdf();
      final budget = DecodeBudget();
      final reader = CosXrefReader(pdf, decodeBudget: budget);
      reader.read();
      expect(identical(reader.decodeBudget, budget), isTrue);
      expect(budget.usedBytes, 16);
    });

    test(
      'a xref stream that inflates past the cap trips the shared budget',
      () {
        final z = ZLibEncoder(level: 9).convert(Uint8List(20 * _mb));
        final b = BytesBuilder();
        b.add(
          latin1.encode(
            '%PDF-1.5\n1 0 obj\n<< /Type /XRef /Size 1 /W [1 2 1] '
            '/Filter /FlateDecode /Length ${z.length} >>\nstream\n',
          ),
        );
        b.add(z);
        b.add(latin1.encode('\nendstream\nendobj\nstartxref\n9\n%%EOF\n'));
        final budget = DecodeBudget();
        expect(
          () => CosXrefReader(b.takeBytes(), decodeBudget: budget).read(),
          throwsA(isA<PdfDecodeLimitExceeded>()),
        );
        expect(budget.tripped, isTrue);
      },
    );
  });

  // --- encrypted files are refused ----------------------------------------
  group('encrypted PDFs are refused', () {
    const encryptedMessage =
        "This PDF is password-protected or encrypted. Dhruva can't read it.";

    const padding = <int>[
      0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, //
      0x56, 0xFF, 0xFA, 0x01, 0x08, 0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68,
      0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
    ];

    String hex(List<int> b) =>
        b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    /// The reviewer's scenario: a real RC4-40 (R2) encrypted PDF whose
    /// empty user password authenticates, with /ObjStm object 3 holding
    /// [bomb] (a zlib stream) encrypted. The guard sees ciphertext there,
    /// which is not zlib, so it could never have inflated and bounded it.
    Uint8List encryptedObjStmPdf(Uint8List bomb) {
      final id = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final o = Uint8List(32); // owner entry; any value works for user auth
      const p = -4;
      final keyInput = BytesBuilder()
        ..add(padding)
        ..add(o)
        ..add([p & 0xFF, (p >> 8) & 0xFF, (p >> 16) & 0xFF, (p >> 24) & 0xFF])
        ..add(id);
      final fileKey = Uint8List.fromList(
        md5.convert(keyInput.takeBytes()).bytes.sublist(0, 5),
      );
      final u = rc4(fileKey, Uint8List.fromList(padding));
      Uint8List objectKey(int n) => Uint8List.fromList(
        md5
            .convert([...fileKey, n & 0xFF, n >> 8 & 0xFF, 0, 0, 0])
            .bytes
            .sublist(0, 10),
      );
      final cipher = rc4(objectKey(3), bomb);

      final b = BytesBuilder();
      final offs = <int>[];
      void w(String s) => b.add(latin1.encode(s));
      w('%PDF-1.5\n');
      for (final obj in [
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [] /Count 0 >>',
      ]) {
        offs.add(b.length);
        w('${offs.length} 0 obj\n$obj\nendobj\n');
      }
      offs.add(b.length);
      w(
        '3 0 obj\n<< /Type /ObjStm /N 1 /First 4 /Filter /FlateDecode '
        '/Length ${cipher.length} >>\nstream\n',
      );
      b.add(cipher);
      w('\nendstream\nendobj\n');
      final xrefAt = b.length;
      w('xref\n0 4\n0000000000 65535 f \n');
      for (final off in offs) {
        w('${off.toString().padLeft(10, '0')} 00000 n \n');
      }
      w(
        'trailer\n<< /Size 4 /Root 1 0 R /ID [<${hex(id)}> <${hex(id)}>] '
        '/Encrypt << /Filter /Standard /V 1 /R 2 /P $p /O <${hex(o)}> '
        '/U <${hex(u)}> >> >>\nstartxref\n$xrefAt\n%%EOF\n',
      );
      return b.takeBytes();
    }

    final bomb = Uint8List.fromList(
      ZLibEncoder(level: 9).convert(Uint8List(20 * _mb)),
    );

    test('the fixture is a real encrypted file the parser opens unasked', () {
      final cos = CosDocument.open(encryptedObjStmPdf(bomb));
      expect(cos.isEncrypted, isTrue, reason: 'empty password authenticates');
    });

    test('the guard reports it as encrypted, not as safe', () {
      final pdf = encryptedObjStmPdf(bomb);
      expect(pdfGuard(pdf), PdfGuardVerdict.encrypted);
      expect(pdfSafeToParse(pdf), isFalse);
    });

    test('the extractor refuses it with the plain message', () {
      expect(
        () => extractDocumentBytes(encryptedObjStmPdf(bomb), 'locked.pdf'),
        throwsA(
          isA<DocumentException>()
              .having((e) => e.kind, 'kind', DocumentFailureKind.encrypted)
              .having((e) => e.message, 'message', encryptedMessage),
        ),
      );
    });

    test('and the decoder cap holds even if the guard were bypassed', () {
      final cos = CosDocument.open(encryptedObjStmPdf(bomb));
      final stream = cos.getObject(3, 0) as CosStream;
      expect(
        () => cos.decodeStreamData(stream),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('an /Encrypt in a cross-reference stream dictionary is refused', () {
      final pdf = Uint8List.fromList(
        latin1.encode(
          '%PDF-1.5\n1 0 obj\n<< /Type /XRef /Size 2 /W [1 2 1] '
          '/Root 9 0 R /Encrypt 7 0 R /Length 4 >>\nstream\nabcd\n'
          'endstream\nendobj\nstartxref\n9\n%%EOF\n',
        ),
      );
      expect(pdfGuard(pdf), PdfGuardVerdict.encrypted);
    });

    test('an /Encrypt hidden by a #-escaped name is still found', () {
      final pdf = Uint8List.fromList(
        latin1.encode('%PDF-1.4\ntrailer\n<< /Size 1 /Encr#79pt 5 0 R >>\n'),
      );
      expect(pdfGuard(pdf), PdfGuardVerdict.encrypted);
    });

    test('an unencrypted file is still safe', () {
      expect(
        pdfGuard(buildTinyPdf(['Hello there, plenty of text here.'])),
        PdfGuardVerdict.safe,
      );
    });
  });
}
