// Personas show one human line, never the raw system prompt, and "Built-in" is
// a gallery section instead of a pill on every card.

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/features/characters/widgets/persona_blurb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every starter persona has a hand-written blurb', () {
    final pack =
        jsonDecode(
              File('assets/characters/starter_pack.json').readAsStringSync(),
            )
            as List<dynamic>;
    final names = [for (final c in pack) (c as Map)['name'] as String];
    expect(names, isNotEmpty);
    for (final n in names) {
      expect(builtInBlurbs[n], isNotNull, reason: 'no blurb for "$n"');
      expect(builtInBlurbs[n]!.length, lessThanOrEqualTo(64), reason: n);
    }
  });

  group('blurbFromPrompt', () {
    test('drops "You are" and a leading name', () {
      expect(
        blurbFromPrompt('You are Writing Coach, a clear and kind editor. When'),
        'A clear and kind editor',
      );
      expect(
        blurbFromPrompt('You are a concise assistant. Answer in few words.'),
        'Concise assistant',
      );
    });

    test('keeps prompts that do not start with "You are"', () {
      expect(
        blurbFromPrompt('Answer like a pirate. Always.'),
        'Answer like a pirate',
      );
    });

    test('caps long lines at a word boundary with an ellipsis', () {
      final s = blurbFromPrompt('You are ${'wordy ' * 30}.');
      expect(s.length, lessThanOrEqualTo(64));
      expect(s.endsWith('…'), isTrue);
    });

    test('empty prompt gives an empty line, not a crash', () {
      expect(blurbFromPrompt(''), '');
    });
  });
}
