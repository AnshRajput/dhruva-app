/// Picks the model the heat guard offers as "a lighter model": the smallest
/// installed file, and only if it is actually smaller than the current one.
library;

import '../../../data/downloads/storage_manager.dart';

InstalledModelInfo? lighterModel(
  List<InstalledModelInfo> installed,
  InstalledModelInfo? current,
) {
  InstalledModelInfo? best;
  for (final m in installed) {
    if (m.id == current?.id) continue;
    if (current != null && m.sizeBytes >= current.sizeBytes) continue;
    if (best == null || m.sizeBytes < best.sizeBytes) best = m;
  }
  return best;
}
