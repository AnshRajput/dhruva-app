/// Loop 5: looks up a character by id for the chat thread AppBar (shows the
/// character's name/avatar in place of the model chip when a conversation is
/// character-bound — see `ChatThreadState.characterId`). Thin wrapper over
/// `characterRepositoryProvider` (`core/di/providers.dart`) — `data/
/// characters` is data-layer, not `features/characters`, so reaching into it
/// from `features/chat` doesn't breach ADR-002's cross-*feature* import ban.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/characters/character_repository.dart';

final characterInfoProvider = FutureProvider.family<CharacterInfo?, int>((
  ref,
  characterId,
) {
  return ref.watch(characterRepositoryProvider).getCharacter(characterId);
});
