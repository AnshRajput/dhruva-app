import 'package:background_downloader/background_downloader.dart' as bg;

import 'download_backend.dart';
import 'download_notifications.dart';

/// Thin adapter over the `background_downloader` plugin. No decision logic
/// lives here — see `download_backend.dart`'s doc comment for why. Needs
/// platform channels, so it's exercised manually/on-device rather than in
/// `flutter test`.
final class BackgroundDownloaderBackend implements DownloadBackend {
  final bg.FileDownloader _downloader;
  final Map<String, bg.DownloadTask> _tasks = {};

  BackgroundDownloaderBackend({bg.FileDownloader? downloader})
    : _downloader = downloader ?? bg.FileDownloader();

  /// Registers the global download notification (D4) and asks for the
  /// Android-13+ POST_NOTIFICATIONS permission. Call once at startup, before
  /// any `enqueue`. Platform-channel only — a no-op on desktop and safe to
  /// call regardless (a denied/skipped permission just means no notification
  /// shows, not a crash). Not covered by `flutter test` (needs the plugin's
  /// native side); the config values it applies are asserted in
  /// `download_notifications_test.dart`.
  Future<void> configureNotifications() async {
    // Run model downloads in an Android foreground service so they SURVIVE the
    // app being backgrounded, navigated away from, or the notification tray
    // being opened. Without this, Android's battery optimizer kills the
    // WorkManager task the moment the app leaves the foreground — the exact
    // "download cancels when I do anything" bug. We only ever download large
    // model files, so `always` is correct (the running notification below is
    // what the foreground service displays).
    await _downloader.configure(
      globalConfig: [(bg.Config.runInForeground, bg.Config.always)],
    );
    final c = dhruvaDownloadNotificationConfig;
    _downloader.configureNotification(
      running: c.running,
      complete: c.complete,
      error: c.error,
      paused: c.paused,
      progressBar: c.progressBar,
      tapOpensFile: c.tapOpensFile,
    );
    final status = await _downloader.permissions.status(
      bg.PermissionType.notifications,
    );
    if (status != bg.PermissionStatus.granted) {
      await _downloader.permissions.request(bg.PermissionType.notifications);
    }
  }

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
    // database (persists across app restarts) and reads it back — no flush
    // onto `updates` happens here. `updates` is already being listened to
    // (DownloadManager's constructor does that before `init` — the only
    // caller of `rehydrate` — runs).
    await _downloader.trackTasks(markDownloadedComplete: true);

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

  @override
  Future<void> flushMissedUpdates() async {
    // The actual "late completion" delivery mechanism: wakes the plugin up
    // and flushes any status/progress updates that happened while this
    // Dart object graph didn't exist onto `updates`. Must run AFTER the
    // caller has rebuilt its active-task map from `rehydrate()`'s result —
    // see that method's doc comment.
    await _downloader.resumeFromBackground();
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
          // The plugin already computes speed + ETA on the progress channel
          // (its own negative sentinels for "unknown"); pass them straight
          // through the seam so the in-app ring can show the same estimate
          // the OS notification does.
          networkSpeedMBs: update.networkSpeed,
          timeRemaining: update.timeRemaining,
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
