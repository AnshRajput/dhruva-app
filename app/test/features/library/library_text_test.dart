import 'package:dhruva/features/library/state/library_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unreadableReason names every failure in plain words', () {
    for (final k in [
      'tooLarge',
      'tooLong',
      'empty',
      'noText',
      'encrypted',
      'unsupported',
      'unsafe',
      'unreadable',
      'whatever',
    ]) {
      expect(unreadableReason(k), isNotEmpty, reason: k);
    }
    expect(unreadableReason('noText'), contains('Scanned'));
    expect(unreadableReason('encrypted'), contains('password'));
  });

  test('fileBadge', () {
    expect(fileBadge('Rental agreement.pdf'), 'PDF');
    expect(fileBadge('ideas.md'), 'MD');
    expect(fileBadge('ideas.markdown'), 'MD');
    expect(fileBadge('notes.txt'), 'TXT');
    expect(fileBadge('noext'), 'FILE');
    expect(fileBadge('trailing.'), 'FILE');
    expect(fileBadge('a.verylongext'), 'FILE');
  });

  group('snippetFor', () {
    const body =
        'Intro paragraph that goes on for a while without mentioning it. '
        'More filler text so the match sits deep inside the file. '
        'The Q4 budget needs approval from finance before the offsite. '
        'And some trailing text after the match to cut off at the end.';

    test('short text is returned whole, on one line', () {
      expect(snippetFor('a\n\n b   c', 'x'), 'a b c');
      expect(snippetFor('', 'x'), '');
    });

    test('centres on the first matching word, with ellipses', () {
      final s = snippetFor(body, 'budget', max: 100);
      expect(s, contains('budget'));
      expect(s.startsWith('… '), isTrue);
      expect(s.endsWith(' …'), isTrue);
      expect(s.length, lessThan(115));
    });

    test('no match falls back to the start', () {
      final s = snippetFor(body, 'zebra', max: 60);
      expect(s.startsWith('Intro'), isTrue);
      expect(s.endsWith(' …'), isTrue);
    });
  });

  test('changedAgo', () {
    final now = DateTime(2026, 11, 2, 12);
    expect(changedAgo(DateTime(2026, 11, 2, 1), now), 'today');
    expect(changedAgo(DateTime(2026, 11, 1, 23), now), 'yesterday');
    expect(changedAgo(DateTime(2026, 10, 30), now), '3 days ago');
    expect(changedAgo(DateTime(2026, 10, 14), now), '2 weeks ago');
    expect(changedAgo(DateTime(2026, 6, 3), now), '3 Jun');
  });
}
