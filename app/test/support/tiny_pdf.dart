import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Builds a minimal, valid, text-bearing PDF with one page per entry of
/// [pages] (Helvetica, one line of text each; an empty string yields a page
/// with no text at all, like a scanned page). Hand-rolled so tests need no
/// binary fixture.
Uint8List buildTinyPdf(List<String> pages) {
  final objects = <String>[];
  // 1 = catalog, 2 = pages, 3 = font, then (page, content) pairs.
  final pageIds = [for (var i = 0; i < pages.length; i++) 4 + i * 2];
  objects
    ..add('<< /Type /Catalog /Pages 2 0 R >>')
    ..add(
      '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] '
      '/Count ${pages.length} >>',
    )
    ..add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pages.length; i++) {
    final pageId = pageIds[i];
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${pageId + 1} 0 R >>',
    );
    final escaped = pages[i]
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    final stream = pages[i].isEmpty
        ? ''
        : 'BT /F1 12 Tf 72 720 Td ($escaped) Tj ET';
    objects.add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefAt = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefAt\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(out.toString()));
}

/// Builds a one-page PDF whose content stream is [content] compressed with
/// FlateDecode. With a highly repetitive [content] this is a decompression
/// bomb: a few KB on disk, hundreds of MB inflated.
Uint8List buildFlatePdf(List<int> content) {
  final data = ZLibEncoder(level: 9).convert(content);
  final b = BytesBuilder();
  final offs = <int>[];
  void w(String s) => b.add(latin1.encode(s));
  w('%PDF-1.4\n');
  for (final o in [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [4 0 R] /Count 1 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>',
  ]) {
    offs.add(b.length);
    w('${offs.length} 0 obj\n$o\nendobj\n');
  }
  offs.add(b.length);
  w('5 0 obj\n<< /Length ${data.length} /Filter /FlateDecode >>\nstream\n');
  b.add(data);
  w('\nendstream\nendobj\n');
  final x = b.length;
  w('xref\n0 6\n0000000000 65535 f \n');
  for (final o in offs) {
    w('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  w('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$x\n%%EOF\n');
  return b.takeBytes();
}
