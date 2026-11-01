import 'package:dhruva/data/docs/bm25.dart';
import 'package:dhruva/data/docs/grounding.dart';
import 'package:flutter_test/flutter_test.dart';

StoredChunk chunk(
  int index,
  String text, {
  int page = 1,
  int docId = 1,
  String docName = 'report.pdf',
  bool paged = true,
}) => StoredChunk(
  docId: docId,
  docName: docName,
  paged: paged,
  index: index,
  page: page,
  text: text,
);

List<StoredChunk> pick(
  List<StoredChunk> chunks,
  String question,
  int budget, {
  int limit = maxExcerpts,
}) => selectExcerpts(
  chunks: chunks,
  index: Bm25Index([for (final c in chunks) c.text]),
  question: question,
  budgetChars: budget,
  limit: limit,
);

void main() {
  group('excerptBudgetChars', () {
    test('leaves room for the answer, template and prompt', () {
      // 4096 ctx - 512 answer - 200 template - 100 prompt tokens (300 chars)
      final budget = excerptBudgetChars(
        contextTokens: 4096,
        maxAnswerTokens: 512,
        promptChars: 300,
      );
      expect(budget, (4096 - 512 - 200 - 100) * charsPerToken);
    });

    test('scales with n_ctx and shrinks with history', () {
      int b(int ctx, int history) => excerptBudgetChars(
        contextTokens: ctx,
        maxAnswerTokens: 512,
        promptChars: history,
      );
      expect(b(8192, 0), greaterThan(b(4096, 0)));
      expect(b(4096, 6000), lessThan(b(4096, 0)));
    });

    test('is zero (never negative) when nothing fits', () {
      expect(
        excerptBudgetChars(
          contextTokens: 1024,
          maxAnswerTokens: 512,
          promptChars: 5000,
        ),
        0,
      );
    });
  });

  group('selectExcerpts', () {
    final chunks = [
      chunk(0, 'Introduction to the project and its goals. ' * 4, page: 1),
      chunk(1, 'The warranty lasts two years and covers parts. ' * 4, page: 2),
      chunk(2, 'Shipping takes one week to most countries. ' * 4, page: 3),
      chunk(3, 'Warranty claims need the original receipt. ' * 4, page: 4),
    ];

    test('packs the best matches within the budget, in document order', () {
      final each = chunks[1].text.length + 24;
      final picked = pick(chunks, 'warranty', each * 2 + 5);
      expect(picked.map((c) => c.index), [1, 3]);
    });

    test('never exceeds the character budget', () {
      for (final budget in [500, 900, 2000, 5000]) {
        final picked = pick(chunks, 'warranty shipping', budget);
        final used = picked.fold<int>(0, (n, c) => n + c.text.length + 24);
        expect(used, lessThanOrEqualTo(budget), reason: 'budget $budget');
      }
    });

    test('respects the excerpt-count limit', () {
      final many = [
        for (var i = 0; i < 20; i++) chunk(i, 'warranty note $i', page: i + 1),
      ];
      expect(pick(many, 'warranty', 100000), hasLength(maxExcerpts));
      expect(pick(many, 'warranty', 100000, limit: 3), hasLength(3));
    });

    test(
      'a question with no keyword match falls back to the document start',
      () {
        final picked = pick(chunks, 'summarize this document', 100000);
        expect(picked.first.index, 0);
        expect(picked, hasLength(chunks.length));
      },
    );

    test('truncates the best chunk when not even one whole chunk fits', () {
      final big = [chunk(0, 'warranty ${'x' * 800}')];
      final picked = pick(big, 'warranty', 500);
      expect(picked, hasLength(1));
      expect(picked.single.text.length, lessThan(500));
      expect(picked.single.text, endsWith('…'));
    });

    test('returns nothing when there is no room at all', () {
      expect(pick(chunks, 'warranty', 0), isEmpty);
      expect(pick(chunks, 'warranty', 100), isEmpty);
      expect(pick(const [], 'warranty', 5000), isEmpty);
    });
  });

  group('buildGroundedPrompt', () {
    test('tags each excerpt with its page and ends with the question', () {
      final g = buildGroundedPrompt(
        question: '  How long is the warranty? ',
        excerpts: [
          chunk(1, 'Warranty lasts two years.', page: 2),
          chunk(3, 'Claims need a receipt.', page: 4),
        ],
      );
      expect(g.prompt, contains('[p.2]\nWarranty lasts two years.'));
      expect(g.prompt, contains('[p.4]\nClaims need a receipt.'));
      expect(g.prompt, contains('Question: How long is the warranty?'));
      expect(g.prompt, contains('only the document excerpts'));
      expect(g.prompt, contains('the document does not'));
      expect(g.prompt, contains('[p.3]')); // the citation instruction
      expect(g.prompt, endsWith('Answer:'));
      // Single document: no file name noise.
      expect(g.prompt, isNot(contains('report.pdf')));
    });

    test('names the file per excerpt when several documents are attached', () {
      final g = buildGroundedPrompt(
        question: 'q',
        excerpts: [
          chunk(0, 'one', docId: 1, docName: 'a.pdf'),
          chunk(0, 'two', docId: 2, docName: 'b.txt', paged: false),
        ],
      );
      expect(g.prompt, contains('[p.1] (a.pdf)'));
      expect(g.prompt, contains('[p.1] (b.txt)'));
    });

    test('says so plainly when no excerpt was found', () {
      final g = buildGroundedPrompt(question: 'q', excerpts: const []);
      expect(g.prompt, contains('(none found)'));
      expect(g.sources, isEmpty);
    });

    test('offers one source per (document, page) with a short snippet', () {
      final g = buildGroundedPrompt(
        question: 'q',
        excerpts: [
          chunk(0, 'first on page two ${'y' * 300}', page: 2),
          chunk(1, 'second on page two', page: 2),
          chunk(2, 'page five', page: 5),
        ],
      );
      expect(g.sources.map((s) => s.page), [2, 5]);
      expect(g.sources.first.snippet, startsWith('first on page two'));
      expect(g.sources.first.snippet.length, lessThanOrEqualTo(161));
      expect(g.sources.first.snippet, endsWith('…'));
    });
  });

  group('citedSources', () {
    const s2 = DocSource(docName: 'a', page: 2, paged: true, snippet: 'x');
    const s4 = DocSource(docName: 'a', page: 4, paged: true, snippet: 'y');
    const s9 = DocSource(docName: 'a', page: 9, paged: true, snippet: 'z');

    test('keeps only the pages the answer cites', () {
      expect(citedSources('It lasts two years [p.2].', [s2, s4, s9]), [s2]);
      expect(
        citedSources('Two years [p.2] and a receipt [p. 9].', [s2, s4, s9]),
        [s2, s9],
      );
    });

    test('understands ranges and lists inside one bracket', () {
      expect(citedSources('See [p.2, 4].', [s2, s4, s9]), [s2, s4]);
      expect(citedSources('See [p.2-4].', [s2, s4, s9]), [s2, s4]);
    });

    test(
      'an uncited or "not in the document" answer lists everything read',
      () {
        expect(citedSources('The document does not say.', [s2, s4]), [s2, s4]);
        // A cite for a page that was never offered is ignored.
        expect(citedSources('Maybe [p.99].', [s2, s4]), [s2, s4]);
      },
    );
  });

  group('source persistence', () {
    test('round-trips through JSON', () {
      const sources = [
        DocSource(docName: 'a.pdf', page: 3, paged: true, snippet: 'hello'),
        DocSource(docName: 'n.txt', page: 1, paged: false, snippet: 'world'),
      ];
      final back = decodeSources(encodeSources(sources));
      expect(back, hasLength(2));
      expect(back[0].label, 'p.3');
      expect(back[1].label, 'part 1');
      expect(back[1].snippet, 'world');
    });

    test('null, empty and garbage decode to nothing', () {
      expect(decodeSources(null), isEmpty);
      expect(decodeSources(''), isEmpty);
      expect(decodeSources('not json'), isEmpty);
      expect(decodeSources('{"a":1}'), isEmpty);
      expect(decodeSources('[1, {"doc": 2}]'), isEmpty);
    });
  });
}
