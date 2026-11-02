/// Settings' Storage section (Amendment 4b): installed model count + total
/// bytes, read straight off `StorageManager` — display-only, no controller
/// of its own. Mutation (delete a model) lives in the Models hub's
/// Installed tab, which this section links to.
///
/// ONE counting rule, shared with that Installed tab: a "model" is a language
/// model (GGUF). Voice files (`sherpa-voice/`) ride the same pipeline but are
/// never counted as models; their size is reported apart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

final class StorageSummary {
  final int modelCount;
  final int totalBytes;

  /// Bytes used by voice files, counted apart from [modelCount]/[totalBytes].
  final int voiceBytes;
  const StorageSummary({
    required this.modelCount,
    required this.totalBytes,
    this.voiceBytes = 0,
  });
}

final storageSummaryProvider = FutureProvider<StorageSummary>((ref) async {
  final manager = ref.watch(storageManagerProvider);
  final all = await manager.listInstalledModels();
  bool isVoice(String repoId) => repoId.startsWith('sherpa-voice/');
  final models = all.where((m) => !isVoice(m.repoId));
  final voice = all.where((m) => isVoice(m.repoId));
  return StorageSummary(
    modelCount: models.length,
    totalBytes: models.fold<int>(0, (sum, m) => sum + m.sizeBytes),
    voiceBytes: voice.fold<int>(0, (sum, m) => sum + m.sizeBytes),
  );
});
