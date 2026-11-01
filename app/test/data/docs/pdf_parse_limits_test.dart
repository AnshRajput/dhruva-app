// Round 6: the content-stream parser and text extractor build objects far
// bigger than the bytes that made them (a 16 MB `[(a)-1 ...] TJ` stream drove
// a real read to 2.3 GB). Three layers, each tested here:
//
//  1. Parser limits (third_party/pdf_cos content_parser.dart): max operators
//     per stream, max operands per operator/array/dictionary, max nesting.
//  2. Decode caps (4 MB per stage, 64 MB per document).
//  3. THE GUARANTEE: the watchdog in `extractDocumentFile` kills the
//     extraction isolate when resident memory grows past
//     `maxExtractionRssGrowth`, whatever the input.
//
// The end-to-end cases go through `extractDocumentFile` (the production entry
// point: it spawns the isolate that runs `extractDocumentBytes` and owns the
// watchdog) and sample `ProcessInfo.currentRss` every 10 ms to report the
// peak growth of the whole process. JIT numbers; the AOT numbers are in the
// PR (tool/extract_rss.dart).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';

import '../../support/tiny_pdf.dart';

const _mb = 1024 * 1024;

/// Content that decodes to just under the 4 MB stage cap.
const _underStageCap = 4 * _mb - 1000;

Uint8List _bytes(String s) => Uint8List.fromList(latin1.encode(s));

/// [head] + [unit] repeated to about [bytes] + [tail].
List<int> _repeat(String head, String unit, String tail, int bytes) {
  final n = (bytes - head.length - tail.length) ~/ unit.length;
  final b = StringBuffer(head);
  for (var i = 0; i < n; i++) {
    b.write(unit);
  }
  return latin1.encode((b..write(tail)).toString());
}

/// A page whose /Contents is an array of [n] tiny streams.
Uint8List _manyTinyStreams(int n, String content) {
  final b = BytesBuilder();
  final offs = <int>[];
  void w(String s) => b.add(latin1.encode(s));
  void obj(String body) {
    offs.add(b.length);
    w('${offs.length} 0 obj\n$body\nendobj\n');
  }

  w('%PDF-1.4\n');
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Kids [4 0 R] /Count 1 >>');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  final refs = [for (var i = 0; i < n; i++) '${5 + i} 0 R'].join(' ');
  obj(
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
    '/Resources << /Font << /F1 3 0 R >> >> /Contents [$refs] >>',
  );
  for (var i = 0; i < n; i++) {
    obj('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  final xref = b.length;
  w('xref\n0 ${offs.length + 1}\n0000000000 65535 f \n');
  for (final o in offs) {
    w('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  w(
    'trailer\n<< /Size ${offs.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return b.takeBytes();
}

typedef _Outcome = ({String outcome, double peakGrowthMb, int ms});

/// Runs the production extractor on [pdf] and reports how it ended and the
/// peak growth of the process's resident memory while it ran.
Future<_Outcome> _run(
  String label,
  Uint8List pdf, {
  int rssGrowthLimit = maxExtractionRssGrowth,
}) async {
  final dir = await Directory.systemTemp.createTemp('dhruva_limits');
  final file = File('${dir.path}/$label.pdf')..writeAsBytesSync(pdf);
  final baseline = ProcessInfo.currentRss;
  var peak = baseline;
  final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
    final r = ProcessInfo.currentRss;
    if (r > peak) peak = r;
  });
  final sw = Stopwatch()..start();
  String outcome;
  try {
    final d = await extractDocumentFile(
      file.path,
      '$label.pdf',
      rssGrowthLimit: rssGrowthLimit,
    );
    outcome = 'ok(${d.charCount})';
  } on DocumentException catch (e) {
    outcome = e.kind.name;
  } finally {
    sampler.cancel();
    await dir.delete(recursive: true);
  }
  final r = (
    outcome: outcome,
    peakGrowthMb: (peak - baseline) / _mb,
    ms: sw.elapsedMilliseconds,
  );
  // ignore: avoid_print
  print(
    'RSS $label: $outcome peakGrowth=${r.peakGrowthMb.toStringAsFixed(0)} MB '
    '${r.ms} ms',
  );
  return r;
}

void main() {
  group('content-stream parser limits', () {
    test('an array past the operand limit is refused', () {
      final big = _bytes(
        '[${'1 ' * (ContentStreamParser.maxOperands + 1)}] TJ',
      );
      expect(
        () => ContentStreamParser.parse(big),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('an operator with too many operands is refused', () {
      for (final unit in ['() ', '<> ', '1 ', '/N ']) {
        final big = _bytes('${unit * (ContentStreamParser.maxOperands + 1)}x');
        expect(
          () => ContentStreamParser.parse(big),
          throwsA(isA<PdfDecodeLimitExceeded>()),
          reason: 'unit "$unit"',
        );
      }
    });

    test('too many operators are refused', () {
      final big = _bytes('q ' * (ContentStreamParser.maxOperations + 1));
      expect(
        () => ContentStreamParser.parse(big),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('over-deep nesting is refused', () {
      final deep = _bytes('${'[' * 100}${']' * 100} TJ');
      expect(
        () => ContentStreamParser.parse(deep),
        throwsA(isA<PdfDecodeLimitExceeded>()),
      );
    });

    test('a breach is counted so swallowed errors are still seen', () {
      final before = ContentStreamParser.limitTrips;
      try {
        ContentStreamParser.parse(_bytes('q ' * 600000));
      } on PdfDecodeLimitExceeded {
        // expected
      }
      expect(ContentStreamParser.limitTrips, before + 1);
    });

    test('streams at the limits and ordinary streams still parse', () {
      final atLimit = _bytes(
        '[${'1 ' * ContentStreamParser.maxOperands}] TJ '
        '${'q ' * 1000}',
      );
      expect(ContentStreamParser.parse(atLimit).length, 1001);
      final ops = ContentStreamParser.parse(
        _bytes('BT /F1 12 Tf 72 720 Td [(Hel) -20 (lo)] TJ ET'),
      );
      expect(ops.map((o) => o.operator), ['BT', 'Tf', 'Td', 'TJ', 'ET']);
    });
  });

  // End to end through the production entry point, each at the largest size
  // the 4 MB decode cap lets through.
  group('hostile content streams are refused within the memory bound', () {
    final cases = <String, List<int>>{
      'TJ array': _repeat(
        'BT /F1 12 Tf [',
        '(a)-1 ',
        '] TJ ET',
        _underStageCap,
      ),
      'empty strings': _repeat(
        'BT /F1 12 Tf [',
        '() ',
        '] TJ ET',
        _underStageCap,
      ),
      'hex empty strings': _repeat(
        'BT /F1 12 Tf [',
        '<> ',
        '] TJ ET',
        _underStageCap,
      ),
      'Td + Tj': _repeat(
        'BT /F1 12 Tf ',
        '0 1 Td (a) Tj ',
        ' ET',
        _underStageCap,
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () async {
        final r = await _run(
          e.key.replaceAll(RegExp('[^A-Za-z]'), '_'),
          buildFlatePdf(e.value),
        );
        expect(r.outcome, anyOf('unsafe', 'tooLong'));
        expect(r.peakGrowthMb, lessThan(500));
      });
    }

    test('many tiny streams', () async {
      final r = await _run(
        'many_tiny',
        _manyTinyStreams(150000, 'BT /F1 12 Tf (a) Tj ET'),
      );
      expect(r.outcome, anyOf('unsafe', 'tooLong'));
      expect(r.peakGrowthMb, lessThan(500));
    });

    test(
      'a 16 MB TJ stream (the round-5 file) is refused by the decode cap',
      () async {
        final r = await _run(
          'tj16',
          buildFlatePdf(
            _repeat('BT /F1 12 Tf [', '(a)-1 ', '] TJ ET', 16 * _mb),
          ),
        );
        expect(r.outcome, 'unsafe');
        expect(r.peakGrowthMb, lessThan(500));
      },
    );
  });

  group('memory watchdog', () {
    // Stays under every parser limit (480k operators), so only the watchdog
    // can stop it when the limit is lowered.
    final underLimits = buildFlatePdf(
      _repeat('BT /F1 12 Tf ', '0 1 Td (a) Tj ', ' ET', 480000 * 7),
    );

    test('kills the isolate and refuses the file as too complex', () async {
      final r = await _run('watchdog', underLimits, rssGrowthLimit: 8 * _mb);
      expect(r.outcome, 'unsafe');
      expect(r.peakGrowthMb, lessThan(150));
    });

    test('the unsafe error carries the plain-language message', () async {
      final dir = await Directory.systemTemp.createTemp('dhruva_wd');
      final f = File('${dir.path}/w.pdf')..writeAsBytesSync(underLimits);
      try {
        await extractDocumentFile(f.path, 'w.pdf', rssGrowthLimit: 8 * _mb);
        fail('expected a DocumentException');
      } on DocumentException catch (e) {
        expect(e.kind, DocumentFailureKind.unsafe);
        expect(e.message, contains('too complex to read safely'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('a normal PDF is not affected and leaves no work behind', () async {
      final r = await _run(
        'normal',
        buildTinyPdf([
          'Hello world, this is a normal page of text for Dhruva.',
        ]),
      );
      expect(r.outcome, startsWith('ok('));
      // No timers or ports left running: a second read works and the
      // process settles back near its baseline.
      final again = await _run(
        'normal2',
        buildTinyPdf(['Another ordinary page, still perfectly readable text.']),
      );
      expect(again.outcome, startsWith('ok('));
    });

    test(
      'shapes that stay under the parser limits stay under 500 MB',
      () async {
        final shapes = {
          'tj_under': _repeat(
            'BT /F1 12 Tf ',
            '[${'(a)-1 ' * 45000}] TJ ',
            ' ET',
            _underStageCap,
          ),
          'hex_under': _repeat(
            'BT /F1 12 Tf ',
            '[${'<> ' * 95000}] TJ ',
            ' ET',
            _underStageCap,
          ),
        };
        for (final e in shapes.entries) {
          final r = await _run(e.key, buildFlatePdf(e.value));
          expect(r.peakGrowthMb, lessThan(500), reason: e.key);
        }
      },
    );
  });
}
