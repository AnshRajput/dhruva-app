// CharactersController: CRUD refresh-after-mutation, duplicate (the
// built-in-can't-edit-in-place escape hatch), and saveImported (the
// parse-then-preview-then-save import path — see import_preview_dialog_test.
// dart for the preview half).

import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/characters/character_card.dart';
import 'package:dhruva/data/characters/character_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/characters/state/characters_controller.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        characterRepositoryProvider.overrideWithValue(
          CharacterRepository(db: db, starterPackLoader: () async => null),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('create adds a character and refreshes the list', () async {
    final id = await container
        .read(charactersControllerProvider.notifier)
        .create(name: 'Coach', personaSystemPrompt: 'Be encouraging.');

    expect(id, isNotNull);
    final state = container.read(charactersControllerProvider).value!;
    expect(state.characters.map((c) => c.name), contains('Coach'));
  });

  test('updateCharacter edits an existing character in place', () async {
    final controller = container.read(charactersControllerProvider.notifier);
    final id = await controller.create(
      name: 'Coach',
      personaSystemPrompt: 'Be encouraging.',
    );

    await controller.updateCharacter(
      id: id!,
      name: 'Coach',
      personaSystemPrompt: 'Be a VERY intense coach.',
    );

    final state = container.read(charactersControllerProvider).value!;
    final updated = state.characters.singleWhere((c) => c.id == id);
    expect(updated.personaSystemPrompt, 'Be a VERY intense coach.');
  });

  test('delete removes a character', () async {
    final controller = container.read(charactersControllerProvider.notifier);
    final id = await controller.create(
      name: 'Temp',
      personaSystemPrompt: 'Temporary.',
    );

    await controller.delete(id!);

    final state = container.read(charactersControllerProvider).value!;
    expect(state.characters.any((c) => c.id == id), isFalse);
  });

  test(
    'duplicate clones a built-in into an editable, non-built-in character',
    () async {
      final now = DateTime.now();
      final builtInId = await db
          .into(db.characters)
          .insert(
            CharactersCompanion.insert(
              name: 'Storyteller',
              personaSystemPrompt: 'Tell vivid stories.',
              isBuiltIn: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await container.read(charactersControllerProvider.future);
      final original = container
          .read(charactersControllerProvider)
          .value!
          .characters
          .singleWhere((c) => c.id == builtInId);

      final newId = await container
          .read(charactersControllerProvider.notifier)
          .duplicate(original);

      final state = container.read(charactersControllerProvider).value!;
      final copy = state.characters.singleWhere((c) => c.id == newId);
      expect(copy.isBuiltIn, isFalse);
      expect(copy.name, 'Storyteller (copy)');
      expect(copy.personaSystemPrompt, 'Tell vivid stories.');
    },
  );

  test('saveImported persists an already-parsed-and-previewed card without '
      'going through CharacterRepository.importCard*', () async {
    final fixture = File(
      'test/fixtures/characters/external_card_v2.json',
    ).readAsStringSync();
    final card = CharacterCardV2.parse(fixture);
    final fields = cardToCharacterFields(card);

    final id = await container
        .read(charactersControllerProvider.notifier)
        .saveImported(fields);

    expect(id, isNotNull);
    final state = container.read(charactersControllerProvider).value!;
    final saved = state.characters.singleWhere((c) => c.id == id);
    expect(saved.name, 'Aria');
    expect(saved.isBuiltIn, isFalse);
    expect(saved.greeting, isNotNull);
  });

  test('characterByIdProvider finds a character not yet in the gallery list '
      "by falling back to a direct repository read (doesn't require the "
      'gallery to have loaded first)', () async {
    final now = DateTime.now();
    final id = await db
        .into(db.characters)
        .insert(
          CharactersCompanion.insert(
            name: 'Direct lookup',
            personaSystemPrompt: 'x',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final character = await container.read(characterByIdProvider(id).future);
    expect(character, isNotNull);
    expect(character!.name, 'Direct lookup');
  });

  test('characterByIdProvider returns null for a missing id', () async {
    final character = await container.read(
      characterByIdProvider(999999).future,
    );
    expect(character, isNull);
  });
}
