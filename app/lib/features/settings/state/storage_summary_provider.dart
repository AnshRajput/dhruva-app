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
import '../../models_hub/state/storage_controller.dart';

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
  // Was a one-shot read of the manager, so it went stale after a download /
  // import / delete while the Models hub (storageControllerProvider, which
  // those paths invalidate) was right. Model count + bytes now come from that
  // same controller, so the two can never disagree.
  final hub = await ref.watch(storageControllerProvider.future);
  final all = await ref.read(storageManagerProvider).listInstalledModels();
  final voice = all.where((m) => m.repoId.startsWith('sherpa-voice/'));
  return StorageSummary(
    modelCount: hub.installed.length,
    totalBytes: hub.totalBytes,
    voiceBytes: voice.fold<int>(0, (sum, m) => sum + m.sizeBytes),
  );
});
