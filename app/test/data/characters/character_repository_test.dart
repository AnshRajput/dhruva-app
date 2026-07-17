import 'dart:convert';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/characters/character_card.dart';
import 'package:dhruva/data/characters/character_repository.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CharacterRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CharacterRepository(db: db, starterPackLoader: () async => null);
  });

  tearDown(() async {
    await db.close();
  });

  group('CRUD', () {
    test('create + get round-trips every field', () async {
      final id = await repo.createCharacter(
        name: 'Coach',
        avatarEmoji: '💪',
        avatarPath: '/data/avatars/coach.png',
        personaSystemPrompt: 'Be an encouraging coach.',
        greeting: 'Ready?',
        exampleDialogues: const ['User: hi\nAssistant: hey!'],
        samplingParams: const SamplingParams(temperature: 0.7),
      );

      final character = await repo.getCharacter(id);
      expect(character, isNotNull);
      expect(character!.name, 'Coach');
      expect(character.avatarEmoji, '💪');
      expect(character.avatarPath, '/data/avatars/coach.png');
      expect(character.personaSystemPrompt, 'Be an encouraging coach.');
      expect(character.greeting, 'Ready?');
      expect(character.exampleDialogues, ['User: hi\nAssistant: hey!']);
      expect(character.samplingParams?.temperature, 0.7);
      expect(character.isBuiltIn, isFalse);
      expect(character.defaultModelId, isNull);
    });

    test(
      'create defaults isBuiltIn to false and tolerates minimal fields',
      () async {
        final id = await repo.createCharacter(
          name: 'Bare',
          personaSystemPrompt: 'p',
        );
        final character = await repo.getCharacter(id);
        expect(character!.isBuiltIn, isFalse);
        expect(character.avatarEmoji, isNull);
        expect(character.greeting, isNull);
        expect(character.exampleDialogues, isEmpty);
        expect(character.samplingParams, isNull);
      },
    );

    test('getCharacter returns null for an unknown id', () async {
      expect(await repo.getCharacter(999), isNull);
    });

    test(
      'createCharacter validates samplingParams before persisting',
      () async {
        expect(
          () => repo.createCharacter(
            name: 'Bad',
            personaSystemPrompt: 'p',
            samplingParams: const SamplingParams(temperature: 99),
          ),
          throwsA(isA<ValidationFailure>()),
        );
        expect(await repo.listCharacters(), isEmpty);
      },
    );

    test('updateCharacter replaces every field and bumps updatedAt', () async {
      final id = await repo.createCharacter(
        name: 'Old',
        personaSystemPrompt: 'old prompt',
      );
      final before = await repo.getCharacter(id);

      // Drift's default DateTimeColumn storage is second-resolution (unix
      // epoch seconds) — a sub-second delay wouldn't reliably move
      // `updatedAt` to a later stored value.
      await Future<void>.delayed(const Duration(seconds: 1, milliseconds: 100));
      await repo.updateCharacter(
        id: id,
        name: 'New',
        personaSystemPrompt: 'new prompt',
        greeting: 'hi',
        avatarEmoji: '🎉',
      );

      final after = await repo.getCharacter(id);
      expect(after!.name, 'New');
      expect(after.personaSystemPrompt, 'new prompt');
      expect(after.greeting, 'hi');
      expect(after.avatarEmoji, '🎉');
      expect(after.updatedAt.isAfter(before!.updatedAt), isTrue);
    });

    test(
      'updateCharacter on an unknown id throws StorageNotFoundFailure',
      () async {
        expect(
          () => repo.updateCharacter(
            id: 999,
            name: 'X',
            personaSystemPrompt: 'p',
          ),
          throwsA(isA<StorageNotFoundFailure>()),
        );
      },
    );

    test('deleteCharacter removes the row', () async {
      final id = await repo.createCharacter(
        name: 'Gone',
        personaSystemPrompt: 'p',
      );
      await repo.deleteCharacter(id);
      expect(await repo.getCharacter(id), isNull);
    });

    test(
      'deleteCharacter on an unknown id throws StorageNotFoundFailure',
      () async {
        expect(
          () => repo.deleteCharacter(999),
          throwsA(isA<StorageNotFoundFailure>()),
        );
      },
    );

    test(
      'listCharacters: built-ins first, then alphabetical within each group',
      () async {
        await repo.createCharacter(name: 'Zed', personaSystemPrompt: 'p');
        await repo.createCharacter(name: 'Anna', personaSystemPrompt: 'p');
        await repo.createCharacter(
          name: 'Built Z',
          personaSystemPrompt: 'p',
          isBuiltIn: true,
        );
        await repo.createCharacter(
          name: 'Built A',
          personaSystemPrompt: 'p',
          isBuiltIn: true,
        );

        final names = (await repo.listCharacters()).map((c) => c.name).toList();
        expect(names, ['Built A', 'Built Z', 'Anna', 'Zed']);
      },
    );

    test('creating two user characters with the same name is allowed — no '
        'uniqueness constraint on Characters.name (dedup only applies to '
        'built-ins by name, see the class doc)', () async {
      final firstId = await repo.createCharacter(
        name: 'Coach',
        personaSystemPrompt: "Version one's persona.",
      );
      final secondId = await repo.createCharacter(
        name: 'Coach',
        personaSystemPrompt: "Version two's persona.",
      );
      expect(firstId, isNot(secondId));
      final all = await repo.listCharacters();
      expect(all.where((c) => c.name == 'Coach'), hasLength(2));
    });

    test('INFO (LOW): createCharacter does not itself reject an empty/'
        'whitespace-only personaSystemPrompt — that validation lives only in '
        'features/characters\' form (live Save-disable) and in card-import\'s '
        'cardToCharacterFields (throws on an empty composed persona). A '
        'caller that bypasses both (there is none in this codebase today) '
        'could persist an empty-persona character; chat_controller_test.dart '
        '\'s "empty persona" test confirms that even if one exists, chat '
        'still never sends an empty system turn — so this is defense-in-'
        'depth-only, not a gate blocker.', () async {
      final id = await repo.createCharacter(
        name: 'Blank',
        personaSystemPrompt: '   ',
      );
      final character = await repo.getCharacter(id);
      expect(character!.personaSystemPrompt, '   ');
    });

    test('listCharacters(builtInsFirst: false) is flat alphabetical', () async {
      await repo.createCharacter(name: 'Zed', personaSystemPrompt: 'p');
      await repo.createCharacter(
        name: 'Anna',
        personaSystemPrompt: 'p',
        isBuiltIn: true,
      );
      final names = (await repo.listCharacters(
        builtInsFirst: false,
      )).map((c) => c.name).toList();
      expect(names, ['Anna', 'Zed']);
    });
  });

  group('chatContextFor', () {
    test('maps persona/greeting/model/sampling into a pure context', () async {
      final id = await repo.createCharacter(
        name: 'Coach',
        personaSystemPrompt: 'Be encouraging.',
        greeting: "Let's go!",
        samplingParams: const SamplingParams(temperature: 0.6),
      );
      final context = await repo.chatContextFor(id);
      expect(context, isNotNull);
      expect(context!.systemPrompt, 'Be encouraging.');
      expect(context.greeting, "Let's go!");
      expect(context.samplingParams?.temperature, 0.6);
      expect(context.defaultModelId, isNull);
    });

    test(
      'returns null for a nonexistent character (deleted characterId)',
      () async {
        expect(await repo.chatContextFor(999), isNull);
      },
    );
  });

  group('card interop wiring', () {
    test('importCardJson creates a new, non-built-in character', () async {
      final json = jsonEncode({
        'data': {
          'name': 'Imported',
          'system_prompt': 'An imported persona.',
          'first_mes': 'Hello from a card!',
        },
      });
      final id = await repo.importCardJson(json);
      final character = await repo.getCharacter(id);
      expect(character!.name, 'Imported');
      expect(character.personaSystemPrompt, 'An imported persona.');
      expect(character.greeting, 'Hello from a card!');
      expect(character.isBuiltIn, isFalse);
    });

    test('importCardFromPng extracts and imports the embedded card', () async {
      final card = characterToCard(
        name: 'PNG Import',
        personaSystemPrompt: 'From a PNG.',
      );
      final png = embedCardInPng(card.toJson());
      final id = await repo.importCardFromPng(png);
      final character = await repo.getCharacter(id);
      expect(character!.name, 'PNG Import');
      expect(character.personaSystemPrompt, 'From a PNG.');
    });

    test(
      'exportCardJson -> importCardJson round-trips a created character',
      () async {
        final id = await repo.createCharacter(
          name: 'Round Trip',
          personaSystemPrompt: 'A persona to round-trip.',
          greeting: 'Hi!',
          exampleDialogues: const ['User: a\nAssistant: b'],
          avatarEmoji: '🔁',
        );
        final exported = await repo.exportCardJson(id);
        final reimportedId = await repo.importCardJson(exported);
        final original = await repo.getCharacter(id);
        final reimported = await repo.getCharacter(reimportedId);

        expect(reimported!.name, original!.name);
        expect(reimported.personaSystemPrompt, original.personaSystemPrompt);
        expect(reimported.greeting, original.greeting);
        expect(reimported.exampleDialogues, original.exampleDialogues);
        expect(reimported.avatarEmoji, original.avatarEmoji);
      },
    );

    test(
      'exportCardPng -> importCardFromPng round-trips a created character',
      () async {
        final id = await repo.createCharacter(
          name: 'PNG Round Trip',
          personaSystemPrompt: 'A PNG persona.',
          greeting: 'From a PNG export!',
        );
        final png = await repo.exportCardPng(id);
        expect(png.sublist(0, 8), pngSignatureForTest);
        final reimportedId = await repo.importCardFromPng(png);
        final reimported = await repo.getCharacter(reimportedId);
        expect(reimported!.name, 'PNG Round Trip');
        expect(reimported.greeting, 'From a PNG export!');
      },
    );

    test(
      'exportCardJson on an unknown id throws StorageNotFoundFailure',
      () async {
        expect(
          () => repo.exportCardJson(999),
          throwsA(isA<StorageNotFoundFailure>()),
        );
      },
    );

    test(
      'importCardJson with malformed JSON surfaces ValidationFailure',
      () async {
        expect(
          () => repo.importCardJson('not json'),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );
  });

  group('seedBuiltInsIfPresent', () {
    test(
      'a repository with the default (asset-absent) loader seeds nothing',
      () async {
        // The default constructor path (no starterPackLoader override) hits
        // rootBundle, which has nothing registered in a plain `flutter_test`
        // VM run — asserting it tolerates that, not just this test's fake.
        final defaultRepo = CharacterRepository(db: db);
        final count = await defaultRepo.seedBuiltInsIfPresent();
        expect(count, 0);
        expect(await defaultRepo.listCharacters(), isEmpty);
      },
    );

    test('seeds every entry from an injected starter-pack JSON', () async {
      final seededRepo = CharacterRepository(
        db: db,
        starterPackLoader: () async => jsonEncode([
          {
            'name': 'Coach',
            'avatarEmoji': '💪',
            'personaSystemPrompt': 'Be encouraging.',
            'greeting': 'Ready?',
            'defaultSampling': {'temperature': 0.7},
          },
          {'name': 'Chef', 'personaSystemPrompt': 'Cook well.'},
        ]),
      );
      final count = await seededRepo.seedBuiltInsIfPresent();
      expect(count, 2);

      final all = await seededRepo.listCharacters();
      expect(all, hasLength(2));
      expect(all.every((c) => c.isBuiltIn), isTrue);
      final coach = all.firstWhere((c) => c.name == 'Coach');
      expect(coach.avatarEmoji, '💪');
      expect(coach.samplingParams?.temperature, 0.7);
    });

    test('seeding twice does not duplicate rows (idempotent upsert)', () async {
      Future<String?> loader() async => jsonEncode([
        {'name': 'Coach', 'personaSystemPrompt': 'v1 persona'},
      ]);
      final seededRepo = CharacterRepository(db: db, starterPackLoader: loader);
      await seededRepo.seedBuiltInsIfPresent();
      await seededRepo.seedBuiltInsIfPresent();

      final all = await seededRepo.listCharacters();
      expect(all, hasLength(1));
      expect(all.single.personaSystemPrompt, 'v1 persona');
    });

    test(
      're-seeding with updated content updates the existing built-in in place',
      () async {
        var persona = 'v1 persona';
        final seededRepo = CharacterRepository(
          db: db,
          starterPackLoader: () async => jsonEncode([
            {'name': 'Coach', 'personaSystemPrompt': persona},
          ]),
        );
        await seededRepo.seedBuiltInsIfPresent();
        persona = 'v2 persona (updated in a later release)';
        await seededRepo.seedBuiltInsIfPresent();

        final all = await seededRepo.listCharacters();
        expect(all, hasLength(1));
        expect(
          all.single.personaSystemPrompt,
          'v2 persona (updated in a later release)',
        );
      },
    );

    test(
      'a user character with the same name as a built-in does not collide',
      () async {
        final seededRepo = CharacterRepository(
          db: db,
          starterPackLoader: () async => jsonEncode([
            {'name': 'Coach', 'personaSystemPrompt': 'built-in persona'},
          ]),
        );
        await seededRepo.createCharacter(
          name: 'Coach',
          personaSystemPrompt: 'user persona',
        );
        await seededRepo.seedBuiltInsIfPresent();

        final all = await seededRepo.listCharacters();
        expect(all, hasLength(2));
        expect(
          all.where((c) => c.isBuiltIn).single.personaSystemPrompt,
          'built-in persona',
        );
        expect(
          all.where((c) => !c.isBuiltIn).single.personaSystemPrompt,
          'user persona',
        );
      },
    );

    test(
      'malformed starter-pack JSON surfaces ValidationFailure, not a crash',
      () async {
        final badRepo = CharacterRepository(
          db: db,
          starterPackLoader: () async => 'not json at all',
        );
        expect(
          () => badRepo.seedBuiltInsIfPresent(),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );
  });
}

/// Local copy of the PNG signature bytes, so this test doesn't need to
/// import `png_text_chunk.dart` just for one assertion.
const pngSignatureForTest = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
