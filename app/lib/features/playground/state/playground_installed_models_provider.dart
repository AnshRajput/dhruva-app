/// Installed GGUF chat models the Playground can pick for a two-model compare.
/// A thin `FutureProvider` over `StorageManager` (data/) — `ref.invalidate`
/// refreshes it, the same pattern the models-hub and chat pickers use.
///
/// The `sherpa-voice/` filter (voice bundles ride the same install pipeline but
/// aren't a valid `EngineService.load` pick) is duplicated here rather than
/// imported from `features/chat`: ADR-002 forbids cross-feature imports, and it
/// is one line, not a shared abstraction worth standing up.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/downloads/storage_manager.dart';

final playgroundInstalledModelsProvider =
    FutureProvider<List<InstalledModelInfo>>((ref) async {
      final models = await ref
          .watch(storageManagerProvider)
          .listInstalledModels();
      return models
          .where((m) => !m.repoId.startsWith('sherpa-voice/'))
          .toList();
    });
