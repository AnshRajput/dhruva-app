/// Installed-model list for the character form's "default model" picker.
/// Deliberate duplication of `features/chat/state/installed_models_
/// provider.dart` (same 4 lines) rather than a cross-feature import —
/// ADR-002 bans `features/` importing `features/`, same precedent as
/// `core/theme/brand_star.dart`'s documented duplication of chat's
/// `DhruvaStar` painter.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/downloads/storage_manager.dart';

final installedModelsProvider = FutureProvider<List<InstalledModelInfo>>((
  ref,
) async {
  final models = await ref.watch(storageManagerProvider).listInstalledModels();
  // Loop 6: same voice-model filter as `features/chat`'s copy of this file
  // (see that file's doc comment) — a character's default model must be a
  // loadable GGUF, never a `sherpa-voice/` ASR/TTS/VAD bundle.
  return models.where((m) => !m.repoId.startsWith('sherpa-voice/')).toList();
});
