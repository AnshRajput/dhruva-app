/// Settings' Storage section (Amendment 4b): installed model count + total
/// bytes, read straight off `StorageManager` — display-only, no controller
/// of its own. Mutation (delete a model) lives in the Models hub's
/// Installed tab, which this section links to.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

final class StorageSummary {
  final int modelCount;
  final int totalBytes;
  const StorageSummary({required this.modelCount, required this.totalBytes});
}

final storageSummaryProvider = FutureProvider<StorageSummary>((ref) async {
  final manager = ref.watch(storageManagerProvider);
  final installed = await manager.listInstalledModels();
  final total = installed.fold<int>(0, (sum, m) => sum + m.sizeBytes);
  return StorageSummary(modelCount: installed.length, totalBytes: total);
});
