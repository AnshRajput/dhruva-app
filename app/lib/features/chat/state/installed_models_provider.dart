/// Installed-model list for the model picker (chat-spec.md §6.1) — thin
/// `FutureProvider` wrapper over `StorageManager`, no mutation of its own
/// (`ref.invalidate` covers refresh, same pattern as models_hub's
/// `modelDetailProvider`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/downloads/storage_manager.dart';

final installedModelsProvider = FutureProvider<List<InstalledModelInfo>>((ref) {
  return ref.watch(storageManagerProvider).listInstalledModels();
});
