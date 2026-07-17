import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/characters/character_seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCharacterSeeds', () {
    test('parses the real shipped starter_pack.json asset', () {
      final raw = File(
        'assets/characters/starter_pack.json',
      ).readAsStringSync();
      final seeds = parseCharacterSeeds(raw);
      expect(seeds, hasLength(10));
      final coach = seeds.firstWhere((s) => s.name == 'Coach');
      expect(coach.avatarEmoji, '💪');
      expect(coach.personaSystemPrompt, contains('accountability partner'));
      expect(coach.greeting, isNotNull);
      // exampleDialogues are {user, assistant} objects in the real asset —
      // folded into "User: ...\nAssistant: ..." strings.
      expect(coach.exampleDialogues, hasLength(2));
      expect(coach.exampleDialogues.first, startsWith('User:'));
      expect(coach.exampleDialogues.first, contains('Assistant:'));
      expect(coach.samplingParams?.temperature, 0.7);
      expect(coach.samplingParams?.topP, 0.9);
      expect(coach.samplingParams?.topK, 40);
    });

    test('every entry in the real asset has a unique, non-empty name', () {
      final raw = File(
        'assets/characters/starter_pack.json',
      ).readAsStringSync();
      final seeds = parseCharacterSeeds(raw);
      final names = seeds.map((s) => s.name).toSet();
      expect(names, hasLength(seeds.length));
      expect(names, everyElement(isNotEmpty));
    });

    test('BUG (MED): "Calm Companion" still hardcodes the US-only "988" crisis '
        'line in one of its example dialogues, despite the orchestrator\'s '
        'explicit fix instruction (BLACKBOARD.md [LOOP-05] docs-writer '
        'HANDOFF, 2026-07-17T19:55: \'US-only "988" crisis line -> '
        'region-neutral referral (global app)\'). personaSystemPrompt WAS '
        'fixed (it says "a local crisis line or emergency services in their '
        'country") but exampleDialogues was missed — this is few-shot text '
        'the model sees and the detail screen displays verbatim, so a non-US '
        'user gets a US-specific number. This asserts the CURRENT (buggy) '
        'content so it fails loudly the moment someone fixes it and forgets '
        'to update this test.', () {
      final raw = File(
        'assets/characters/starter_pack.json',
      ).readAsStringSync();
      final seeds = parseCharacterSeeds(raw);
      final calmCompanion = seeds.firstWhere((s) => s.name == 'Calm Companion');
      final allText = [
        calmCompanion.personaSystemPrompt,
        ...calmCompanion.exampleDialogues,
      ].join('\n');
      expect(
        allText,
        contains('988'),
        reason:
            'if this now fails, the "988" reference has been removed — '
            'flip this to `isNot(contains(\'988\'))` and close BUG (MED) '
            'from the Loop-5 QA review.',
      );
    });

    test('a minimal entry needs only name + personaSystemPrompt', () {
      final seeds = parseCharacterSeeds(
        jsonEncode([
          {'name': 'Minimal', 'personaSystemPrompt': 'Just be helpful.'},
        ]),
      );
      expect(seeds, hasLength(1));
      expect(seeds.single.name, 'Minimal');
      expect(seeds.single.avatarEmoji, isNull);
      expect(seeds.single.greeting, isNull);
      expect(seeds.single.exampleDialogues, isEmpty);
      expect(seeds.single.samplingParams, isNull);
    });

    test('plain-string exampleDialogues entries are kept as-is', () {
      final seeds = parseCharacterSeeds(
        jsonEncode([
          {
            'name': 'X',
            'personaSystemPrompt': 'p',
            'exampleDialogues': ['already a plain string'],
          },
        ]),
      );
      expect(seeds.single.exampleDialogues, ['already a plain string']);
    });

    test('invalid JSON throws ValidationFailure', () {
      expect(
        () => parseCharacterSeeds('{not json'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a non-array JSON root throws ValidationFailure', () {
      expect(
        () => parseCharacterSeeds(jsonEncode({'name': 'not an array'})),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('an entry missing "name" throws ValidationFailure', () {
      expect(
        () => parseCharacterSeeds(
          jsonEncode([
            {'personaSystemPrompt': 'p'},
          ]),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('an entry missing "personaSystemPrompt" throws ValidationFailure', () {
      expect(
        () => parseCharacterSeeds(
          jsonEncode([
            {'name': 'X'},
          ]),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a non-object array entry throws ValidationFailure', () {
      expect(
        () => parseCharacterSeeds(jsonEncode(['just a string'])),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
}
