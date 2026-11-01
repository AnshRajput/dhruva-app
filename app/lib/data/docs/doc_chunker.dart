/// Splits extracted document text into overlapping, page-tagged chunks for
/// keyword retrieval (`bm25.dart`). Pure Dart, no I/O: safe to run inside an
/// isolate (see `document_extractor.dart`).
library;

/// Target chunk length in characters.
const chunkSize = 800;

/// Characters shared between two neighbouring chunks of the same page.
const chunkOverlap = 100;

/// Size of the synthetic "parts" a page-less TXT/MD file is cut into so its
/// chunks still have a locator to cite.
const textSectionSize = 3000;

/// The text of one page (or one synthetic part of a page-less file).
final class PageText {
  /// 1-based.
  final int page;
  final String text;
  const PageText(this.page, this.text);
}

/// One retrievable slice of a document. A chunk never spans two pages, so
/// its [page] is always exact.
final class DocChunk {
  /// 0-based position in the whole document.
  final int index;

  /// 1-based page (or part, for page-less files).
  final int page;
  final String text;
  const DocChunk({required this.index, required this.page, required this.text});
}

/// Collapses runs of spaces/tabs and 3+ newlines so chunks carry content, not
/// PDF layout whitespace.
String normalizeWhitespace(String raw) {
  return raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t\f\v ]+'), ' ')
      .replaceAll(RegExp(r' ?\n ?'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Chunks [pages] into ~[size]-character windows overlapping by [overlap],
/// preferring to end a window at a paragraph, sentence or word boundary.
/// Pages with no text are skipped. Chunk indices run across the whole
/// document in page order.
List<DocChunk> chunkPages(
  List<PageText> pages, {
  int size = chunkSize,
  int overlap = chunkOverlap,
}) {
  assert(size > 0 && overlap >= 0 && overlap < size);
  final chunks = <DocChunk>[];
  for (final page in pages) {
    final text = normalizeWhitespace(page.text);
    if (text.isEmpty) continue;
    var start = 0;
    while (start < text.length) {
      var end = start + size;
      if (end >= text.length) {
        end = text.length;
      } else {
        end = _breakPoint(text, start, end, size);
      }
      final piece = text.substring(start, end).trim();
      if (piece.isNotEmpty) {
        chunks.add(
          DocChunk(index: chunks.length, page: page.page, text: piece),
        );
      }
      if (end >= text.length) break;
      // Step back by the overlap, then forward to the next word start so a
      // chunk never opens mid-word. Always make forward progress.
      var next = end - overlap;
      if (next <= start) next = end;
      while (next < end && !_isSpace(text.codeUnitAt(next - 1))) {
        next++;
      }
      start = next;
    }
  }
  return chunks;
}

/// Cuts a page-less [text] into [textSectionSize]-character parts (at a
/// paragraph/line/word boundary) numbered from 1.
List<PageText> splitIntoSections(String text, {int size = textSectionSize}) {
  final clean = normalizeWhitespace(text);
  if (clean.isEmpty) return const [];
  final sections = <PageText>[];
  var start = 0;
  while (start < clean.length) {
    var end = start + size;
    if (end >= clean.length) {
      end = clean.length;
    } else {
      end = _breakPoint(clean, start, end, size);
    }
    sections.add(PageText(sections.length + 1, clean.substring(start, end)));
    start = end;
  }
  return sections;
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x0a;

/// The best cut in `(end - size ~/ 4, end]`: paragraph break, else sentence
/// end, else any space; falls back to the hard [end].
int _breakPoint(String text, int start, int end, int size) {
  final floor = end - size ~/ 4;
  var sentence = -1;
  var space = -1;
  for (var i = end; i > floor && i > start; i--) {
    final c = text.codeUnitAt(i - 1);
    if (c == 0x0a && i >= 2 && text.codeUnitAt(i - 2) == 0x0a) return i;
    if (sentence < 0 && (c == 0x20 || c == 0x0a) && i >= 2) {
      final prev = text.codeUnitAt(i - 2);
      if (prev == 0x2e || prev == 0x21 || prev == 0x3f) sentence = i;
    }
    if (space < 0 && _isSpace(c)) space = i;
  }
  if (sentence > 0) return sentence;
  if (space > 0) return space;
  return end;
}
