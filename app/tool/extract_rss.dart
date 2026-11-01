// Measures peak resident-memory growth of `extractDocumentFile` on PDFs.
//   dart compile exe tool/extract_rss.dart -o /tmp/extract_rss
//   [RSS_LIMIT_MB=50] /tmp/extract_rss a.pdf b.pdf ...
// RSS_LIMIT_MB lowers the watchdog limit to prove it fires.
// Prints one line per file: outcome, peak RSS growth over the pre-call
// baseline (sampled every 5 ms), and wall time. Used to verify the extraction
// watchdog (maxExtractionRssGrowth) end to end in AOT.
import 'dart:async';
import 'dart:io';

import 'package:dhruva/data/docs/document_extractor.dart';

Future<void> main(List<String> args) async {
  final limitMb = int.tryParse(Platform.environment['RSS_LIMIT_MB'] ?? '');
  final limit = limitMb == null ? maxExtractionRssGrowth : limitMb << 20;
  for (final path in args) {
    final base = ProcessInfo.currentRss;
    var peak = base;
    final sw = Stopwatch()..start();
    final t = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final r = ProcessInfo.currentRss;
      if (r > peak) peak = r;
    });
    String outcome;
    try {
      final d = await extractDocumentFile(
        path,
        path.split('/').last,
        rssGrowthLimit: limit,
      );
      outcome = 'ok chars=${d.charCount}';
    } on DocumentException catch (e) {
      outcome = e.kind.name;
    }
    t.cancel();
    stdout.writeln(
      '${path.split('/').last}\t$outcome\t'
      'peakGrowth=${((peak - base) / 1048576).toStringAsFixed(0)} MB\t'
      '${sw.elapsedMilliseconds} ms',
    );
  }
}
