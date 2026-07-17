/// Installed-model list for the model picker (chat-spec.md §6.1) — thin
/// `FutureProvider` wrapper over `StorageManager`, no mutation of its own
/// (`ref.invalidate` covers refresh, same pattern as models_hub's
/// `modelDetailProvider`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/downloads/storage_manager.dart';

final installedModelsProvider = FutureProvider<List<InstalledModelInfo>>((
  ref,
) async {
  final models = await ref.watch(storageManagerProvider).listInstalledModels();
  // Loop 6: voice models (ASR/TTS/VAD) ride the same `DownloadManager` ->
  // `InstalledModels` pipeline as GGUF chat models (see
  // `core/di/providers.dart`'s `voiceModelDownloadRequest`, repoId prefix
  // `sherpa-voice/`) so they get resumable/integrity-checked downloads for
  // free — but they are never a valid pick for `EngineService.load()` (a
  // whisper/piper onnx bundle isn't a GGUF), so this picker filters them
  // out at the one place chat actually loads a model from the list.
  return models.where((m) => !m.repoId.startsWith('sherpa-voice/')).toList();
});
