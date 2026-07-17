import 'package:dhruva/features/chat/state/think_tag_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitThinkContent', () {
    test('no think tag at all: everything is content', () {
      final split = splitThinkContent('just an answer');
      expect(split.reasoning, '');
      expect(split.content, 'just an answer');
      expect(split.reasoningOpen, isFalse);
    });

    test('closed think block: reasoning and content separated', () {
      final split = splitThinkContent(
        '<think>working it out</think>final answer',
      );
      expect(split.reasoning, 'working it out');
      expect(split.content, 'final answer');
      expect(split.reasoningOpen, isFalse);
    });

    test('text before the opener is content', () {
      final split = splitThinkContent('preamble<think>reasoning</think>answer');
      expect(split.reasoning, 'reasoning');
      expect(split.content, 'preambleanswer');
    });

    test('unclosed think tag: rest of buffer is reasoning, still open', () {
      final split = splitThinkContent('<think>still going');
      expect(split.reasoning, 'still going');
      expect(split.content, '');
      expect(split.reasoningOpen, isTrue);
    });

    test('empty string', () {
      final split = splitThinkContent('');
      expect(split.reasoning, '');
      expect(split.content, '');
      expect(split.reasoningOpen, isFalse);
    });
  });

  group('QA (Loop-4 attack list #3): hostile think-tag cases', () {
    test('think-only response with no trailing content: content empty, '
        'reasoning populated', () {
      final split = splitThinkContent('<think>only reasoning</think>');
      expect(split.reasoning, 'only reasoning');
      expect(split.content, isEmpty);
      expect(split.reasoningOpen, isFalse);
    });

    test(
      'BUG repro: nested <think> tags — only the FIRST opener/closer pair is '
      'recognized (documented in this file\'s library doc), so the inner '
      'opener/closer are swallowed into reasoning/content as LITERAL text '
      'instead of being stripped, and would render as stray tag text in the '
      'chat bubble',
      () {
        final split = splitThinkContent(
          '<think>outer <think>inner</think> tail</think>after',
        );
        // The first </think> found closes the block — it's the one right
        // after "inner", not the real outer closer.
        expect(split.reasoning, 'outer <think>inner');
        // Everything past that point, including the leftover literal
        // "</think>" from the (never separately recognized) outer closer,
        // ends up in content — visible to the user as raw tag text.
        expect(split.content, ' tail</think>after');
        expect(split.content, contains('</think>'));
      },
    );

    test('BUG repro: two sequential (non-nested) think blocks — only the first '
        'is extracted; the second block\'s <think>/</think> tags leak into '
        'content as literal text', () {
      final split = splitThinkContent(
        '<think>first</think>middle<think>second</think>end',
      );
      expect(split.reasoning, 'first');
      expect(
        split.content,
        'middle<think>second</think>end',
        reason:
            'the second <think>...</think> pair is never recognized as a '
            'reasoning block — it is left verbatim in the visible content, '
            'exactly the "second literal <think>" case the library doc '
            'calls "vanishingly rare" but a real reasoning model doing a '
            'second reasoning pass mid-answer would trigger it',
      );
    });

    test(
      '100KB reasoning block: split cost stays well under one flush interval '
      '(parse-cost assertion, not a frame-timing one)',
      () {
        final huge = 'a' * 100000;
        final raw = '<think>$huge</think>done';
        final sw = Stopwatch()..start();
        // Simulates the repeated re-derivation ChatController._flush does on
        // every 100ms tick against a buffer that keeps growing.
        for (var i = 0; i < 20; i++) {
          splitThinkContent(safeThinkPrefix(raw, isFinal: false));
        }
        sw.stop();
        // 20 re-parses of a 100KB buffer in well under a flush interval
        // (100ms) — generous ceiling, this is a regression guard, not a
        // tight budget.
        expect(sw.elapsedMilliseconds, lessThan(100));
      },
    );
  });

  group('safeThinkPrefix', () {
    test('withholds the tag-length holdback when not final', () {
      const raw = '0123456789';
      final safe = safeThinkPrefix(raw, isFinal: false);
      expect(safe.length, raw.length - thinkTagHoldback);
    });

    test('returns everything when final', () {
      const raw = '0123456789';
      expect(safeThinkPrefix(raw, isFinal: true), raw);
    });

    test('never negative-lengths a short buffer', () {
      expect(safeThinkPrefix('ab', isFinal: false), 'ab');
    });

    test('a closing tag split across two flushes is never misclassified', () {
      // Simulates two token deltas: "<think>reasoning</thi" then "nk>rest".
      const firstChunk = '<think>reasoning</thi';
      final firstSafe = safeThinkPrefix(firstChunk, isFinal: false);
      // The holdback keeps the dangling "</thi" prefix out of this flush's
      // classification — splitting the safe prefix must still show
      // reasoningOpen (the real closer hasn't been committed yet).
      expect(splitThinkContent(firstSafe).reasoningOpen, isTrue);

      const full = '<think>reasoning</think>rest';
      final finalSplit = splitThinkContent(
        safeThinkPrefix(full, isFinal: true),
      );
      expect(finalSplit.reasoning, 'reasoning');
      expect(finalSplit.content, 'rest');
      expect(finalSplit.reasoningOpen, isFalse);
    });
  });
}
