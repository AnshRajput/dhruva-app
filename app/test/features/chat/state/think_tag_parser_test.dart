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
