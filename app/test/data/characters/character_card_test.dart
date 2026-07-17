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

    test('an empty string input throws ValidationFailure, not a crash', () {
      expect(
        () => CharacterCardV2.parse(''),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a wrong/unknown "spec_version" is tolerated (read loosely, not '
        'hard-asserted — real-world cards vary here per the class doc)', () {
      final card = CharacterCardV2.parse(
        jsonEncode({
          'spec': 'not_a_real_spec',
          'spec_version': '99.9-bogus',
          'data': {'name': 'X', 'system_prompt': 'p'},
        }),
      );
      expect(card.name, 'X');
    });

    test(
      'extra unknown top-level "data" fields are silently dropped, not a crash '
      '(attack list #1: hostile-but-plausible interop input)',
      () {
        final card = CharacterCardV2.parse(
          jsonEncode({
            'data': {
              'name': 'X',
              'system_prompt': 'p',
              'totally_unknown_field': 'whatever',
              'nested_garbage': {
                'a': {
                  'b': {
                    'c': [1, 2, 3, null, true],
                  },
                },
              },
            },
          }),
        );
        expect(card.name, 'X');
        expect(card.systemPrompt, 'p');
      },
    );

    test('a very large "system_prompt" string does not crash or truncate', () {
      final huge = 'x' * 500000;
      final card = CharacterCardV2.parse(
        jsonEncode({
          'data': {'name': 'X', 'system_prompt': huge},
        }),
      );
      expect(card.systemPrompt.length, 500000);
    });

    test(
      'a non-object "data" value (e.g. an array) throws ValidationFailure',
      () {
        expect(
          () => CharacterCardV2.parse(
            jsonEncode({
              'data': [1, 2, 3],
            }),
          ),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );
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

    test('BUG (HIGH): a card whose extensions.dhruva.samplingParams has a '
        'wrong-typed field (e.g. temperature as a String) crashes with a raw '
        'TypeError instead of a typed ValidationFailure — attack list #1 '
        'requires "typed failure or graceful skip, never crash" for hostile '
        'import content, and this is reachable straight from an imported '
        'community card (SamplingParams.fromJson does `json["temperature"] as '
        'num?`, which throws TypeError on a non-num value; nothing between '
        'here and characters_gallery_screen._import\'s `on ValidationFailure` '
        'catch narrows that). Root cause is in SamplingParams.fromJson '
        '(data/chat/models/sampling_params.dart), shared by every '
        'samplingParams JSON consumer, not just card import.', () {
      final card = CharacterCardV2(
        name: 'X',
        systemPrompt: 'p',
        extensions: {
          'dhruva': {
            'samplingParams': {'temperature': 'not a number'},
          },
        },
      );
      // Documents CURRENT behavior (the bug): this is a raw TypeError, not
      // a ValidationFailure. Once fixed, this assertion should become
      // `throwsA(isA<ValidationFailure>())` and the test renamed.
      expect(() => cardToCharacterFields(card), throwsA(isA<TypeError>()));
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

    test('an empty (0-byte) file throws ValidationFailure, not a crash', () {
      expect(
        () => extractCardFromPng(Uint8List(0)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('INFO (LOW): a "chara" chunk with a corrupted CRC-32 is still read '
        'successfully — png_text_chunk.dart\'s reader deliberately does not '
        'verify chunk CRCs (see _parseChunks: "skip the trailing CRC; write '
        'side recomputes it"), so bit-corruption that still decodes as valid '
        'base64/JSON is silently accepted rather than rejected. This does not '
        'violate "never crash" (attack list #1) — it never throws — but it is '
        'a data-integrity gap worth a deliberate `// ponytail:`-style comment '
        'in the source if this is an intentional simplification (PNG viewers '
        'don\'t reject bad-CRC ancillary chunks either, so real-world impact '
        'is low; flagging for visibility, not blocking the gate).', () {
      final card = characterToCard(name: 'X', personaSystemPrompt: 'p');
      final png = embedCardInPng(card.toJson());
      // embedTextChunk inserts the tEXt "chara" chunk immediately before
      // IEND, so its 4-byte CRC is exactly the 4 bytes preceding IEND's
      // fixed 12-byte block (4 length + 4 type "IEND" + 0 data + 4 crc).
      final corrupted = Uint8List.fromList(png);
      final lastCrcByteOfCharaChunk = png.length - 12 - 1;
      corrupted[lastCrcByteOfCharaChunk] ^= 0xFF;
      // Still parses — the reader never checks the CRC it just read.
      final extracted = extractCardFromPng(corrupted);
      expect(extracted, card.toJson());
    });

    test('embedding into a PNG that already carries a "chara" card (as an iTXt '
        'chunk, the shape a real third-party SillyTavern-style tool would use) '
        'replaces it, not duplicates', () {
      // Hand-built uncompressed iTXt "chara" chunk, independent of this
      // codebase's own tEXt writer — simulates a card from another tool.
      final builder = BytesBuilder();
      builder.add(ascii.encode('chara'));
      builder.addByte(0);
      builder.addByte(0); // uncompressed
      builder.addByte(0);
      builder.addByte(0); // empty language tag
      builder.addByte(0); // empty translated keyword
      final oldPayload = base64Encode(
        utf8.encode(
          jsonEncode({
            'data': {'name': 'Old Card'},
          }),
        ),
      );
      builder.add(utf8.encode(oldPayload));
      final pngWithThirdPartyCard = _pngWithChunks([
        ('iTXt', builder.toBytes()),
      ]);

      final newCard = characterToCard(
        name: 'New Card',
        personaSystemPrompt: 'p',
      );
      final replaced = embedCardInPng(
        newCard.toJson(),
        avatarPng: pngWithThirdPartyCard,
      );

      final extracted = extractCardFromPng(replaced);
      final extractedData = extracted['data'] as Map<String, dynamic>;
      expect(extractedData['name'], 'New Card');
      // Only one "chara" chunk survives — re-parsing manually to count.
      var count = 0;
      var offset = 8;
      final view = ByteData.sublistView(replaced);
      while (offset < replaced.length) {
        final length = view.getUint32(offset, Endian.big);
        final type = ascii.decode(replaced.sublist(offset + 4, offset + 8));
        if ((type == 'tEXt' || type == 'iTXt') &&
            latin1
                .decode(replaced.sublist(offset + 8, offset + 8 + 5))
                .startsWith('chara')) {
          count++;
        }
        offset += 8 + length + 4;
        if (type == 'IEND') break;
      }
      expect(count, 1);
    });
  });
}

/// Builds a minimal valid PNG (signature + IHDR + [chunks] + IEND), each
/// correctly CRC'd, for tests that need to simulate a PNG shaped by a tool
/// other than this codebase's own writer.
Uint8List _pngWithChunks(List<(String, Uint8List)> chunks) {
  final out = BytesBuilder();
  out.add(pngSignature);
  void writeChunk(String type, List<int> data) {
    final typeBytes = ascii.encode(type);
    final length = ByteData(4)..setUint32(0, data.length, Endian.big);
    final crcInput = Uint8List.fromList([...typeBytes, ...data]);
    final crc = ByteData(4)..setUint32(0, crc32(crcInput), Endian.big);
    out.add(length.buffer.asUint8List());
    out.add(typeBytes);
    out.add(data);
    out.add(crc.buffer.asUint8List());
  }

  // Minimal valid IHDR for a 1x1 image (same shape as the well-known
  // placeholder PNG this file already trusts elsewhere).
  final ihdr = ByteData(13)
    ..setUint32(0, 1, Endian.big) // width
    ..setUint32(4, 1, Endian.big) // height
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // color type (RGBA)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  writeChunk('IHDR', ihdr.buffer.asUint8List());
  for (final (type, data) in chunks) {
    writeChunk(type, data);
  }
  writeChunk('IEND', const []);
  return out.toBytes();
}
