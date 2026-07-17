/// Downloads screen state (T5 §4): accumulates `DownloadManager.progress`
/// broadcast events into a `taskId -> DownloadProgress` map so the screen
/// can render every task's latest known state (the stream itself only ever
/// emits one update at a time, not a full snapshot).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
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
}
