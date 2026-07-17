/// Characters gallery/CRUD state (Loop 5). One list-shaped `AsyncNotifier`
/// over `CharacterRepository` — same shape as `StorageController`
/// (models_hub): load once, refresh-after-every-mutation, surface a typed
/// `actionError` instead of swallowing it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/characters/character_card.dart';
import '../../../data/characters/character_repository.dart';
import '../../../data/chat/models/sampling_params.dart';

final class CharactersState {
  final List<CharacterInfo> characters;

  /// Last create/update/delete/import failure, surfaced honestly rather
  /// than swallowed — same convention as `StorageState.actionError`.
  final AppFailure? actionError;

  const CharactersState({this.characters = const [], this.actionError});
}

final charactersControllerProvider =
    AsyncNotifierProvider<CharactersController, CharactersState>(
      CharactersController.new,
    );

/// Looks up one character by id — `charactersControllerProvider`'s list is
/// the source of truth (watched here so any create/update/delete/import
/// mutation refreshes this too), falling back to a direct repository read
/// so a deep-linked detail/edit screen doesn't have to wait on the gallery
/// having loaded first.
final characterByIdProvider = FutureProvider.family<CharacterInfo?, int>((
  ref,
  id,
) async {
  final listed = await ref.watch(charactersControllerProvider.future);
  for (final c in listed.characters) {
    if (c.id == id) return c;
  }
  return ref.read(characterRepositoryProvider).getCharacter(id);
});

class CharactersController extends AsyncNotifier<CharactersState> {
  CharacterRepository get _repo => ref.read(characterRepositoryProvider);

  @override
  Future<CharactersState> build() async {
    return CharactersState(characters: await _repo.listCharacters());
  }

  Future<void> refresh() async {
    state = AsyncData(
      CharactersState(characters: await _repo.listCharacters()),
    );
  }

  Future<int?> create({
    required String name,
    String? avatarEmoji,
    String? avatarPath,
    required String personaSystemPrompt,
    String? greeting,
    List<String> exampleDialogues = const [],
    int? defaultModelId,
    SamplingParams? samplingParams,
  }) => _guarded(
    () => _repo.createCharacter(
      name: name,
      avatarEmoji: avatarEmoji,
      avatarPath: avatarPath,
      personaSystemPrompt: personaSystemPrompt,
      greeting: greeting,
      exampleDialogues: exampleDialogues,
      defaultModelId: defaultModelId,
      samplingParams: samplingParams,
    ),
  );

  /// Named `updateCharacter`, not `update` — `AsyncNotifier` already has an
  /// inherited `update(fn)` (optimistic-update helper) with an incompatible
  /// signature; overriding it by accident silently breaks that base-class
  /// contract instead of failing loudly, so this uses a distinct name.
  Future<int?> updateCharacter({
    required int id,
    required String name,
    String? avatarEmoji,
    String? avatarPath,
    required String personaSystemPrompt,
    String? greeting,
    List<String> exampleDialogues = const [],
    int? defaultModelId,
    SamplingParams? samplingParams,
  }) => _guarded(() async {
    await _repo.updateCharacter(
      id: id,
      name: name,
      avatarEmoji: avatarEmoji,
      avatarPath: avatarPath,
      personaSystemPrompt: personaSystemPrompt,
      greeting: greeting,
      exampleDialogues: exampleDialogues,
      defaultModelId: defaultModelId,
      samplingParams: samplingParams,
    );
    return id;
  });

  /// Built-ins can't be edited in place (`seedBuiltInsIfPresent` upserts
  /// them by name on every app start, so a direct edit would just be
  /// overwritten) or deleted — this clones one into an ordinary, editable
  /// user character instead. See the detail screen's "Duplicate to edit"
  /// affordance.
  Future<int?> duplicate(CharacterInfo original) => _guarded(
    () => _repo.createCharacter(
      name: '${original.name} (copy)',
      avatarEmoji: original.avatarEmoji,
      avatarPath: original.avatarPath,
      personaSystemPrompt: original.personaSystemPrompt,
      greeting: original.greeting,
      exampleDialogues: original.exampleDialogues,
      defaultModelId: original.defaultModelId,
      samplingParams: original.samplingParams,
    ),
  );

  Future<void> delete(int id) => _guarded(() async {
    await _repo.deleteCharacter(id);
    return null;
  });

  /// Saves an already-parsed-and-previewed import (see
  /// `character_card.dart`'s `cardToCharacterFields` — the gallery screen
  /// parses+previews before calling this, rather than going through
  /// `CharacterRepository.importCard*` directly, so the user sees exactly
  /// what will be created before anything is persisted).
  Future<int?> saveImported(ImportedCharacterFields fields) => _guarded(
    () => _repo.createCharacter(
      name: fields.name,
      avatarEmoji: fields.avatarEmoji,
      personaSystemPrompt: fields.personaSystemPrompt,
      greeting: fields.greeting,
      exampleDialogues: fields.exampleDialogues,
      samplingParams: fields.samplingParams,
    ),
  );

  Future<int?> _guarded(Future<int?> Function() action) async {
    try {
      final result = await action();
      await refresh();
      return result;
    } on AppFailure catch (e) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(
          CharactersState(characters: current.characters, actionError: e),
        );
      }
      return null;
    }
  }
}
