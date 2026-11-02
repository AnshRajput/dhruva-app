/// The chat-model download that is running right now, if any, for surfaces that
/// must say "downloading" instead of "no model installed" (Today's brief, Ask
/// opened from Prep / Plan my day). Lives in `core` so features never import
/// `features/models_hub` (ADR-002). Voice bundles are not chat models and are
/// ignored.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/downloads/download_manager.dart';
import 'providers.dart';

bool _active(DownloadProgress p) =>
    !p.repoId.startsWith('sherpa-voice/') &&
    switch (p.state) {
      DownloadState.queued ||
      DownloadState.running ||
      DownloadState.paused ||
      DownloadState.verifying => true,
      DownloadState.complete ||
      DownloadState.failed ||
      DownloadState.canceled => false,
    };

/// True once every byte is here but the model is not yet registered (hashing
/// the file, then writing its row): "100%" would be a promise the app cannot
/// keep for another moment, so every download surface says "Finishing up…".
bool downloadFinishing(DownloadProgress p) {
  if (p.state == DownloadState.verifying) return true;
  final t = p.totalBytes;
  return t != null && t > 0 && p.downloadedBytes >= t;
}

/// 0..1 while bytes are still arriving; null while the total is unknown or the
/// download is [downloadFinishing] (show an indeterminate bar, not 100%).
double? downloadFraction(DownloadProgress p) {
  final t = p.totalBytes;
  if (t == null || t <= 0 || downloadFinishing(p)) return null;
  return (p.downloadedBytes / t).clamp(0.0, 1.0);
}

final modelDownloadProvider = StreamProvider<DownloadProgress?>((ref) async* {
  final manager = await ref.watch(downloadManagerProvider.future);
  final tasks = <String, DownloadProgress>{};
  yield null;
  await for (final u in manager.progress) {
    tasks[u.taskId] = u;
    final active = tasks.values.where(_active).toList();
    yield active.isEmpty ? null : active.first;
  }
});
