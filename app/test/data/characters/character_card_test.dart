import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/characters/character_card.dart';
import 'package:dhruva/data/characters/png_text_chunk.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CharacterCardV2 JSON parsing', () {
    test('parses a well-formed card', () {
      final card = CharacterCardV2.parse(
        jsonEncode({
          'spec': 'chara_card_v2',
          'spec_version': '2.0',
          'data': {
            'name': 'Coach',
            'first_mes': 'Hi!',
            'system_prompt': 'Be encouraging.',
          },
        }),
      );
      expect(card.name, 'Coach');
      expect(card.firstMes, 'Hi!');
      expect(card.systemPrompt, 'Be encouraging.');
    });

    test(
      'invalid JSON throws ValidationFailure, not a raw FormatException',
      () {
        expect(
          () => CharacterCardV2.parse('{not json'),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test('JSON root that is not an object throws ValidationFailure', () {
      expect(
        () => CharacterCardV2.parse('[1, 2, 3]'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('missing "data" object throws ValidationFailure', () {
      expect(
        () => CharacterCardV2.parse(jsonEncode({'spec': 'chara_card_v2'})),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('missing/empty "data.name" throws ValidationFailure', () {
      expect(
        () => CharacterCardV2.parse(
          jsonEncode({
            'data': {'name': '   '},
          }),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('cardToCharacterFields', () {
    test(
      'a card with only system_prompt uses it verbatim as personaSystemPrompt',
      () {
        final card = CharacterCardV2(
          name: 'X',
          systemPrompt: 'Full persona here.',
        );
        final fields = cardToCharacterFields(card);
        expect(fields.personaSystemPrompt, 'Full persona here.');
      },
    );

    test('a card with description/personality/scenario (no system_prompt) '
        'composes a sane persona', () {
      final card = CharacterCardV2(
        name: 'Aria',
        description: 'A night-shift barista.',
        personality: 'Sarcastic but warm.',
        scenario: 'Late night, empty cafe.',
      );
      final fields = cardToCharacterFields(card);
      expect(
        fields.personaSystemPrompt,
        contains('Description: A night-shift barista.'),
      );
      expect(
        fields.personaSystemPrompt,
        contains('Personality: Sarcastic but warm.'),
      );
      expect(
        fields.personaSystemPrompt,
        contains('Scenario: Late night, empty cafe.'),
      );
    });

    test('a card with no persona content at all throws ValidationFailure', () {
      final card = CharacterCardV2(name: 'Empty');
      expect(
        () => cardToCharacterFields(card),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('first_mes maps to greeting, blank first_mes maps to null', () {
      final withGreeting = cardToCharacterFields(
        CharacterCardV2(name: 'X', systemPrompt: 'p', firstMes: 'Hello!'),
      );
      expect(withGreeting.greeting, 'Hello!');

      final withoutGreeting = cardToCharacterFields(
        CharacterCardV2(name: 'X', systemPrompt: 'p', firstMes: '  '),
      );
      expect(withoutGreeting.greeting, isNull);
    });

    test('mes_example <START>-delimited blocks map to exampleDialogues', () {
      final fields = cardToCharacterFields(
        CharacterCardV2(
          name: 'X',
          systemPrompt: 'p',
          mesExample: '<START>\nBlock one\n<START>\nBlock two',
        ),
      );
      expect(fields.exampleDialogues, ['Block one', 'Block two']);
    });

    test('extensions.dhruva.avatarEmoji/samplingParams are restored', () {
      final fields = cardToCharacterFields(
        CharacterCardV2(
          name: 'X',
          systemPrompt: 'p',
          extensions: {
            'dhruva': {
              'avatarEmoji': '🎈',
              'samplingParams': const SamplingParams(
                temperature: 0.42,
              ).toJson(),
            },
          },
        ),
      );
      expect(fields.avatarEmoji, '🎈');
      expect(fields.samplingParams?.temperature, 0.42);
    });
  });

  group(
    'characterToCard / cardToCharacterFields round trip (our own export)',
    () {
      test('re-importing our own export reproduces every mapped field', () {
        const original = ImportedCharacterFields(
          name: 'Coach',
          personaSystemPrompt:
              'You are Coach, an encouraging accountability partner.',
          greeting: "Hey! Let's talk about your goals.",
          exampleDialogues: [
            'User: hi\nAssistant: hello!',
            'User: bye\nAssistant: goodbye!',
          ],
          avatarEmoji: '💪',
          samplingParams: SamplingParams(temperature: 0.7, topP: 0.9, topK: 40),
        );

        final card = characterToCard(
          name: original.name,
          personaSystemPrompt: original.personaSystemPrompt,
          greeting: original.greeting,
          exampleDialogues: original.exampleDialogues,
          avatarEmoji: original.avatarEmoji,
          samplingParams: original.samplingParams,
        );

        // Through JSON, exactly as export/import would really do it.
        final reparsed = CharacterCardV2.fromJson(
          jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
        );
        final reimported = cardToCharacterFields(reparsed);

        expect(reimported.name, original.name);
        expect(reimported.personaSystemPrompt, original.personaSystemPrompt);
        expect(reimported.greeting, original.greeting);
        expect(reimported.exampleDialogues, original.exampleDialogues);
        expect(reimported.avatarEmoji, original.avatarEmoji);
        expect(
          reimported.samplingParams?.toJson(),
          original.samplingParams?.toJson(),
        );
      });

      test(
        'a character with no greeting/dialogues/emoji/sampling round-trips too',
        () {
          final card = characterToCard(
            name: 'Minimal',
            personaSystemPrompt: 'Just a prompt.',
          );
          final reimported = cardToCharacterFields(
            CharacterCardV2.fromJson(
              jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
            ),
          );
          expect(reimported.name, 'Minimal');
          expect(reimported.personaSystemPrompt, 'Just a prompt.');
          expect(reimported.greeting, isNull);
          expect(reimported.exampleDialogues, isEmpty);
          expect(reimported.avatarEmoji, isNull);
          expect(reimported.samplingParams, isNull);
        },
      );
    },
  );

  group('a real external V2 card fixture parses into a sane Character', () {
    test(
      'the fixture composes a sane persona from description/personality/scenario',
      () {
        final fixture = File(
          'test/fixtures/characters/external_card_v2.json',
        ).readAsStringSync();
        final card = CharacterCardV2.parse(fixture);
        expect(card.name, 'Aria');

        final fields = cardToCharacterFields(card);
        expect(fields.name, 'Aria');
        expect(fields.personaSystemPrompt, contains('Description:'));
        expect(fields.personaSystemPrompt, contains('night-shift barista'));
        expect(fields.personaSystemPrompt, contains('Personality:'));
        expect(fields.personaSystemPrompt, contains('Scenario:'));
        expect(fields.greeting, contains('We\'re technically closed'));
        expect(fields.exampleDialogues, hasLength(2));
        expect(fields.exampleDialogues.first, contains('Rough night?'));
        // This fixture carries no dhruva extension.
        expect(fields.avatarEmoji, isNull);
        expect(fields.samplingParams, isNull);
      },
    );
  });

  group('PNG embedding', () {
    test(
      'embedCardInPng / extractCardFromPng round-trip on the placeholder',
      () {
        final card = characterToCard(
          name: 'PNG Character',
          personaSystemPrompt: 'A persona embedded in a PNG.',
          greeting: 'Hi from inside a PNG!',
        );
        final png = embedCardInPng(card.toJson());
        expect(png.sublist(0, 8), pngSignature);

        final extracted = extractCardFromPng(png);
        expect(extracted, card.toJson());

        final reimported = cardToCharacterFields(
          CharacterCardV2.fromJson(extracted),
        );
        expect(reimported.name, 'PNG Character');
        expect(reimported.greeting, 'Hi from inside a PNG!');
      },
    );

    test('a PNG with no embedded card throws ValidationFailure', () {
      expect(
        () => extractCardFromPng(placeholderPng),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'a non-PNG file throws ValidationFailure, not a raw FormatException',
      () {
        expect(
          () =>
              extractCardFromPng(Uint8List.fromList(utf8.encode('not a png'))),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test(
      'a "chara" chunk with garbage (non-base64) payload throws ValidationFailure',
      () {
        final png = embedTextChunk(placeholderPng, 'chara', '!!!not base64!!!');
        expect(
          () => extractCardFromPng(png),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test(
      'a "chara" chunk whose payload decodes to non-JSON throws ValidationFailure',
      () {
        final garbage = base64Encode(utf8.encode('this is not json'));
        final png = embedTextChunk(placeholderPng, 'chara', garbage);
        expect(
          () => extractCardFromPng(png),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test(
      'a "chara" chunk whose payload decodes to a JSON array (not object) throws',
      () {
        final arrayPayload = base64Encode(utf8.encode(jsonEncode([1, 2, 3])));
        final png = embedTextChunk(placeholderPng, 'chara', arrayPayload);
        expect(
          () => extractCardFromPng(png),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );
  });
}
