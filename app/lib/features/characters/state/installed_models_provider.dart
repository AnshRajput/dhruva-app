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

final installedModelsProvider = FutureProvider<List<InstalledModelInfo>>((ref) {
  return ref.watch(storageManagerProvider).listInstalledModels();
});
