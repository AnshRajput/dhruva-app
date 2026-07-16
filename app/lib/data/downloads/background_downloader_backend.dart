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
