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
      expect(seeds, hasLength(14));
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

    test('ships the everyday assistants: writing, explaining, translating, '
        'short answers, studying', () {
      final raw = File(
        'assets/characters/starter_pack.json',
      ).readAsStringSync();
      final byName = {for (final s in parseCharacterSeeds(raw)) s.name: s};
      for (final name in [
        'Writing Coach',
        "Explain Like I'm New",
        'Hindi-English Translator',
        'Concise Assistant',
        'Study Buddy',
      ]) {
        final seed = byName[name];
        expect(seed, isNotNull, reason: name);
        expect(seed!.personaSystemPrompt.length, greaterThan(100));
        expect(seed.greeting, isNotEmpty);
        expect(seed.samplingParams, isNotNull);
        seed.samplingParams!.validate();
      }
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

    test(
      'FIXED (QA MED): "Calm Companion" no longer hardcodes the US-only '
      '"988" crisis line anywhere — personaSystemPrompt AND exampleDialogues '
      'both use region-neutral referral language (global app, not US-only).',
      () {
        final raw = File(
          'assets/characters/starter_pack.json',
        ).readAsStringSync();
        final seeds = parseCharacterSeeds(raw);
        final calmCompanion = seeds.firstWhere(
          (s) => s.name == 'Calm Companion',
        );
        final allText = [
          calmCompanion.personaSystemPrompt,
          ...calmCompanion.exampleDialogues,
        ].join('\n');
        expect(allText, isNot(contains('988')));
      },
    );

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
