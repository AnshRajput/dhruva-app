import 'dart:convert';
import 'dart:typed_data';

/// A stream object for [buildPdfObjects]: [dict] are extra dictionary
/// entries (no `/Length`), [data] the raw payload.
final class PdfStreamBody {
  final String dict;
  final List<int> data;
  const PdfStreamBody(this.dict, this.data);
  PdfStreamBody.text(this.dict, String text) : data = latin1.encode(text);
}

/// Builds a PDF whose object `i + 1` is `bodies[i]`: a [String] (the raw
/// object body) or a [PdfStreamBody]. Object 1 must be the catalog. Writes a
/// classic xref table. Lets tests hand-craft any page tree, font or form.
Uint8List buildPdfObjects(List<Object> bodies, {String trailerExtra = ''}) {
  final b = BytesBuilder();
  final offs = <int>[];
  void w(String s) => b.add(latin1.encode(s));
  w('%PDF-1.4\n');
  for (var i = 0; i < bodies.length; i++) {
    offs.add(b.length);
    w('${i + 1} 0 obj\n');
    final body = bodies[i];
    if (body is PdfStreamBody) {
      w('<< /Length ${body.data.length} ${body.dict} >>\nstream\n');
      b.add(body.data);
      w('\nendstream');
    } else {
      w(body as String);
    }
    w('\nendobj\n');
  }
  final x = b.length;
  w('xref\n0 ${bodies.length + 1}\n0000000000 65535 f \n');
  for (final o in offs) {
    w('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  w(
    'trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R $trailerExtra >>\n'
    'startxref\n$x\n%%EOF\n',
  );
  return b.takeBytes();
}

/// One page (object 4, content object 5) with the fonts/XObjects in
/// [resources] and [content] as its content stream. [extra] objects are
/// numbered from 6.
Uint8List buildOnePagePdf(
  String content, {
  String resources = '/Font << /F1 3 0 R >>',
  String font =
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
  List<Object> extra = const [],
}) => buildPdfObjects([
  '<< /Type /Catalog /Pages 2 0 R >>',
  '<< /Type /Pages /Kids [4 0 R] /Count 1 >>',
  font,
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << $resources >> /Contents 5 0 R >>',
  PdfStreamBody.text('', content),
  ...extra,
]);
