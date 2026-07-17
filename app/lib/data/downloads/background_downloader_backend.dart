import 'package:background_downloader/background_downloader.dart' as bg;

import 'download_backend.dart';

/// Thin adapter over the `background_downloader` plugin. No decision logic
/// lives here — see `download_backend.dart`'s doc comment for why. Needs
/// platform channels, so it's exercised manually/on-device rather than in
/// `flutter test`.
final class BackgroundDownloaderBackend implements DownloadBackend {
  final bg.FileDownloader _downloader;
  final Map<String, bg.DownloadTask> _tasks = {};

  BackgroundDownloaderBackend({bg.FileDownloader? downloader})
    : _downloader = downloader ?? bg.FileDownloader();

  @override
  Stream<BackendUpdate> get updates => _downloader.updates
      .map(_toBackendUpdate)
      .where((u) => u != null)
      .cast<BackendUpdate>();

  @override
  Future<bool> enqueue(BackendDownloadRequest request) async {
    final task = bg.DownloadTask(
      taskId: request.taskId,
      url: request.url.toString(),
      filename: request.fileName,
      directory: request.directoryPath,
      baseDirectory: bg.BaseDirectory.root,
      allowPause: request.allowPause,
      updates: bg.Updates.statusAndProgress,
      metaData: request.metaData,
    );
    _tasks[request.taskId] = task;
    return _downloader.enqueue(task);
  }

  @override
  Future<bool> pause(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    return _downloader.pause(task);
  }

  @override
  Future<bool> resume(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    return _downloader.resume(task);
  }

  @override
  Future<bool> cancel(String taskId) => _downloader.cancelTaskWithId(taskId);

  @override
  Future<String?> filePathFor(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return null;
    return task.filePath();
  }

  @override
  Future<List<RehydratedTask>> rehydrate() async {
    // `trackTasks` activates the plugin's own SQLite-backed task-tracking
    // database (persists across app restarts); `resumeFromBackground` wakes
    // it up and flushes any status/progress updates that happened while
    // this Dart object graph didn't exist (app killed/backgrounded) onto
    // `updates` — that's the actual "late completion" delivery mechanism.
    // Both must run after `updates` is being listened to, which
    // `DownloadManager`'s constructor already does before `init()` (the
    // only caller of `rehydrate`) runs.
    await _downloader.trackTasks(markDownloadedComplete: true);
    await _downloader.resumeFromBackground();

    final records = await _downloader.database.allRecords();
    final rehydrated = <RehydratedTask>[];
    for (final record in records) {
      // Repopulate the taskId -> DownloadTask map too, or pause/resume/
      // filePathFor on a rehydrated task would fail post-restart even
      // though the task itself is still tracked. `record.task` is the base
      // `Task` type; every task this backend ever enqueues is a
      // `DownloadTask` (see `enqueue` above), but guard the cast rather than
      // assume it for whatever the plugin's database happens to hold.
      final task = record.task;
      if (task is bg.DownloadTask) _tasks[task.taskId] = task;
      rehydrated.add(
        RehydratedTask(taskId: task.taskId, metaData: task.metaData),
      );
    }
    return rehydrated;
  }

  BackendUpdate? _toBackendUpdate(bg.TaskUpdate update) {
    if (update.task.taskId.isEmpty) return null;
    switch (update) {
      case bg.TaskStatusUpdate():
        return BackendStatusUpdate(
          update.task.taskId,
          status: _toBackendStatus(update.status),
          errorMessage: update.exception?.description,
        );
      case bg.TaskProgressUpdate():
        return BackendProgressUpdate(
          update.task.taskId,
          progress: update.progress,
          expectedFileSizeBytes: update.hasExpectedFileSize
              ? update.expectedFileSize
              : null,
        );
    }
  }

  BackendTaskStatus _toBackendStatus(bg.TaskStatus status) => switch (status) {
    bg.TaskStatus.enqueued ||
    bg.TaskStatus.waitingToRetry => BackendTaskStatus.enqueued,
    bg.TaskStatus.running => BackendTaskStatus.running,
    bg.TaskStatus.paused => BackendTaskStatus.paused,
    bg.TaskStatus.complete => BackendTaskStatus.complete,
    bg.TaskStatus.failed => BackendTaskStatus.failed,
    bg.TaskStatus.canceled => BackendTaskStatus.canceled,
    bg.TaskStatus.notFound => BackendTaskStatus.notFound,
  };
}
