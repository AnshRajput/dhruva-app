import 'package:dhruva/data/docs/bm25.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tokenize', () {
    test(
      'lowercases, strips punctuation, drops stopwords and 1-char tokens',
      () {
        expect(tokenize('The Quick, brown fox! It is a "dog".'), [
          'quick',
          'brown',
          'fox',
          'dog',
        ]);
      },
    );

    test('folds plain plurals but not "ss"', () {
      expect(tokenize('invoices glass'), ['invoice', 'glass']);
    });

    test('keeps digits and non-Latin letters', () {
      expect(tokenize('Q3-2024 revenue über 日本語'), [
        'q3',
        '2024',
        'revenue',
        'über',
        '日本語',
      ]);
    });
  });

  group('Bm25Index', () {
    final texts = [
      'The warranty covers parts and labor for two years from purchase.',
      'Shipping takes five to seven business days within the country.',
      'To reset the device hold the power button for ten seconds.',
      'Warranty claims require the original receipt and serial number.',
    ];
    final index = Bm25Index(texts);

    test('ranks the best keyword match first', () {
      final hits = index.search('how long is the warranty');
      expect(hits.first.index, anyOf(0, 3));
      expect(hits.map((h) => h.index).toSet(), {0, 3});
    });

    test('a rarer term outweighs a common one', () {
      // "receipt" appears once; "warranty" twice. A query with both should
      // put the chunk containing both rare + common terms first.
      final hits = index.search('warranty receipt');
      expect(hits.first.index, 3);
    });

    test('plural in the query matches singular in the text', () {
      expect(index.search('reset buttons').first.index, 2);
    });

    test('no usable keywords or no match yields no hits', () {
      expect(index.search('the and of'), isEmpty);
      expect(index.search('zzzz'), isEmpty);
      expect(Bm25Index(const []).search('anything'), isEmpty);
    });

    test(
      'scores are positive, sorted descending, ties keep document order',
      () {
        final twin = Bm25Index(['alpha beta', 'alpha beta']);
        final hits = twin.search('alpha');
        expect(hits.map((h) => h.index), [0, 1]);
        final all = index.search('warranty');
        for (var i = 0; i + 1 < all.length; i++) {
          expect(all[i].score, greaterThanOrEqualTo(all[i + 1].score));
        }
        expect(all.every((h) => h.score > 0), isTrue);
      },
    );

    test('shorter chunks win on equal term frequency (length norm)', () {
      final idx = Bm25Index(['warranty ${'filler ' * 40}', 'warranty filler']);
      expect(idx.search('warranty').first.index, 1);
    });
  });
}
