import 'package:dhruva/data/docs/doc_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

String _sentences(int n) =>
    List.generate(n, (i) => 'Sentence number $i is here.').join(' ');

void main() {
  test('short page becomes one chunk tagged with its page', () {
    final chunks = chunkPages(const [PageText(3, 'Just a short page.')]);
    expect(chunks, hasLength(1));
    expect(chunks.single.page, 3);
    expect(chunks.single.index, 0);
    expect(chunks.single.text, 'Just a short page.');
  });

  test('long text is split into ~800 char chunks that overlap', () {
    final text = _sentences(120); // ~3.1k chars
    final chunks = chunkPages([PageText(1, text)]);
    expect(chunks.length, greaterThan(3));
    for (final c in chunks) {
      expect(c.text.length, lessThanOrEqualTo(chunkSize));
      expect(c.text, isNotEmpty);
    }
    // Neighbouring chunks share text: the head of chunk n+1 appears in the
    // tail of chunk n (the ~100 char overlap).
    for (var i = 0; i + 1 < chunks.length; i++) {
      final tail = chunks[i].text;
      final head = chunks[i + 1].text.split(' ').take(3).join(' ');
      expect(tail, contains(head), reason: 'chunk $i should overlap $i+1');
    }
    // Nothing is lost: every sentence survives intact in some chunk.
    for (var i = 0; i < 120; i++) {
      expect(
        chunks.any((c) => c.text.contains('Sentence number $i is here.')),
        isTrue,
        reason: 'sentence $i',
      );
    }
  });

  test('chunks never open mid-word', () {
    final chunks = chunkPages([PageText(1, _sentences(120))]);
    for (final c in chunks) {
      expect(c.text, matches(RegExp(r'^(Sentence|number|is|here\.|\d+)( |$)')));
    }
  });

  test('chunks never span pages and indices run across the document', () {
    final chunks = chunkPages([
      PageText(1, _sentences(40)),
      const PageText(2, '   '), // blank page is skipped
      PageText(5, _sentences(40)),
    ]);
    expect(chunks.map((c) => c.page).toSet(), {1, 5});
    expect(
      [for (final c in chunks) c.index],
      [for (var i = 0; i < chunks.length; i++) i],
    );
    final firstOnPage5 = chunks.indexWhere((c) => c.page == 5);
    expect(firstOnPage5, greaterThan(0));
    expect(chunks.take(firstOnPage5).every((c) => c.page == 1), isTrue);
  });

  test('prefers paragraph and sentence boundaries', () {
    final para = '${'a' * 700}.\n\n${'b' * 700}.';
    final chunks = chunkPages([PageText(1, para)]);
    expect(chunks.first.text, endsWith('.'));
    expect(chunks.first.text, isNot(contains('b')));
  });

  test('a word longer than a chunk still makes progress', () {
    final chunks = chunkPages([PageText(1, 'x' * 2000)]);
    expect(chunks.length, greaterThanOrEqualTo(3));
    expect(chunks.every((c) => c.text.length <= chunkSize), isTrue);
  });

  test('whitespace is normalized', () {
    expect(
      normalizeWhitespace('a   b\t\tc\r\n\r\n\r\n\r\nd  \n  e'),
      'a b c\n\nd\ne',
    );
  });

  test('page-less text is cut into numbered sections at line boundaries', () {
    final sections = splitIntoSections(_sentences(300)); // ~7.8k chars
    expect(sections.length, greaterThanOrEqualTo(3));
    expect(
      [for (final s in sections) s.page],
      [for (var i = 1; i <= sections.length; i++) i],
    );
    expect(sections.every((s) => s.text.length <= textSectionSize), isTrue);
    expect(splitIntoSections('   \n '), isEmpty);
  });
}
