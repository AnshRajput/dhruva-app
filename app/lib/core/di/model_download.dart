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

/// 0..1, or null while the total is unknown.
double? downloadFraction(DownloadProgress p) {
  final t = p.totalBytes;
  if (t == null || t <= 0) return null;
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
