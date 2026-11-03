/// "Is the active model under 1B parameters?" One rule, shared by the Ask
/// composer note, Today's "Rewrite in my words" and the Draft sheet.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/downloads/storage_manager.dart';
import '../../data/hf_api/mobile_suitability.dart';
import 'engine_session.dart';
import 'providers.dart';

/// Shown once at the Ask composer (and the Draft sheet) under a small model.
const smallModelNote = 'Small model: fastest, least accurate. Check facts.';

/// Files under this size are taken as small when the repo name carries no
/// parameter count.
const _smallModelBytes = 600 * 1024 * 1024;

/// True when [m] is under 1B parameters: the count in its repo name when it
/// has one, else a file under ~600 MB. A null model is not small (nothing to
/// warn about).
bool isSmallModel(InstalledModelInfo? m) {
  if (m == null) return false;
  final b = paramBillionsFromName(m.repoId);
  return b != null ? b < 1 : m.sizeBytes < _smallModelBytes;
}

/// Whether the model that would answer now is small: the one loaded, else the
/// most recently used text model (what Today and Inbox would load).
final activeModelIsSmallProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(storageManagerProvider);
  final loadedId = ref.watch(loadedModelIdProvider);
  final loaded = loadedId == null
      ? null
      : await storage.getInstalledModel(loadedId);
  if (loaded != null) return isSmallModel(loaded);
  return isSmallModel((await storage.listTextModels()).firstOrNull);
});
