/// Downloads screen state (T5 §4): accumulates `DownloadManager.progress`
/// broadcast events into a `taskId -> DownloadProgress` map so the screen
/// can render every task's latest known state (the stream itself only ever
/// emits one update at a time, not a full snapshot).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/downloads/download_manager.dart';

final downloadsControllerProvider =
    AsyncNotifierProvider<DownloadsController, Map<String, DownloadProgress>>(
      DownloadsController.new,
    );

class DownloadsController extends AsyncNotifier<Map<String, DownloadProgress>> {
  StreamSubscription<DownloadProgress>? _sub;

  @override
  Future<Map<String, DownloadProgress>> build() async {
    final manager = await ref.watch(downloadManagerProvider.future);
    ref.onDispose(() => unawaited(_sub?.cancel()));
    _sub = manager.progress.listen((update) {
      final next = Map<String, DownloadProgress>.from(state.value ?? const {});
      next[update.taskId] = update;
      state = AsyncData(next);
    });
    return const {};
  }

  Future<void> pause(String taskId) async =>
      (await ref.read(downloadManagerProvider.future)).pause(taskId);

  Future<void> resume(String taskId) async =>
      (await ref.read(downloadManagerProvider.future)).resume(taskId);

  /// Cancels at the backend, then removes [taskId] from the visible map
  /// immediately — once cancelled/failed, `DownloadManager` itself forgets
  /// the task, so nothing will emit a fresh terminal event to clear it for
  /// us.
  Future<void> cancel(String taskId) async {
    final manager = await ref.read(downloadManagerProvider.future);
    await manager.cancel(taskId);
    final next = Map<String, DownloadProgress>.from(state.value ?? const {})
      ..remove(taskId);
    state = AsyncData(next);
  }

  /// Re-enqueues a failed row's download. `DownloadProgress` (this
  /// controller's only source of truth — see the class doc) doesn't carry
  /// the original `DownloadRequest` — no `Uri`, checksum, quant, or license
  /// — so the request is rebuilt from what a failed row *does* know
  /// (repoId, fileName, and the last known `totalBytes`, which
  /// `DownloadManager._emit` always backfills from the original
  /// `expectedSizeBytes`). The resolve URL is a pure `repoId`+`fileName`
  /// builder, so that part reconstructs exactly; checksum/quant/license are
  /// lost on a retry started from this screen (size-only integrity check
  /// still applies) — retrying from the model detail screen keeps full
  /// metadata.
  Future<void> retry(String taskId) async {
    final progress = state.value?[taskId];
    if (progress == null) return;
    final manager = await ref.read(downloadManagerProvider.future);
    final request = DownloadRequest(
      repoId: progress.repoId,
      fileName: progress.fileName,
      url: ref
          .read(hfApiClientProvider)
          .resolveDownloadUrl(progress.repoId, progress.fileName),
      expectedSizeBytes: progress.totalBytes ?? 0,
    );
    try {
      final freeBytes =
          (await ref.read(deviceInfoServiceProvider).getStorageInfo())
              .freeBytes;
      await manager.enqueue(request, freeBytes: freeBytes);
      // Success: the manager's own progress stream emits a fresh `queued`
      // update for this taskId, applied by the subscription in `build()`.
    } on AppFailure catch (e) {
      final next = Map<String, DownloadProgress>.from(state.value ?? const {});
      next[taskId] = DownloadProgress(
        taskId: progress.taskId,
        repoId: progress.repoId,
        fileName: progress.fileName,
        state: DownloadState.failed,
        downloadedBytes: 0,
        totalBytes: progress.totalBytes,
        errorMessage: e.message,
        failure: e,
      );
      state = AsyncData(next);
    }
  }
}
