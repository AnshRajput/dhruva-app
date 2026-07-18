/// Neutral seam over the download plugin (`background_downloader`), mirror
/// of `engine_bindings/engine_service.dart`'s abstraction: `DownloadManager`
/// (the business logic — progress mapping, integrity checks, drift writes)
/// depends only on this interface and is fully unit-testable against
/// [FakeDownloadBackend]. Only [BackgroundDownloaderBackend] touches the
/// plugin's platform channels, which don't exist under `flutter test` — so
/// that adapter is exercised manually/on-device, not in the unit suite
/// (same carve-out as `llama_engine_service.dart`, COVERAGE FLOOR SCOPE).
library;

/// One HTTP-range-resumable file download request.
final class BackendDownloadRequest {
  final String taskId;
  final Uri url;
  final String fileName;

  /// Absolute directory the file is saved into.
  final String directoryPath;
  final bool allowPause;

  /// Opaque app-level payload the backend persists alongside the task (the
  /// real plugin stores this in its own on-disk task-tracking database) and
  /// hands back unchanged from [DownloadBackend.rehydrate] — this is how
  /// `DownloadManager` reconstructs a `DownloadRequest` after an app
  /// restart, when its in-memory active-task map is gone but a task is
  /// still running (or already finished) at the OS level.
  final String metaData;

  const BackendDownloadRequest({
    required this.taskId,
    required this.url,
    required this.fileName,
    required this.directoryPath,
    this.allowPause = true,
    this.metaData = '',
  });
}

/// One task the backend already knew about before `rehydrate` was called —
/// either still running, or finished while nothing was listening (app
/// killed/backgrounded). [metaData] is the same opaque string the task was
/// [BackendDownloadRequest.metaData] at enqueue time; the backend never
/// interprets it, only stores and returns it.
final class RehydratedTask {
  final String taskId;
  final String metaData;
  const RehydratedTask({required this.taskId, required this.metaData});
}

enum BackendTaskStatus {
  enqueued,
  running,
  paused,
  complete,
  failed,
  canceled,
  notFound,
}

sealed class BackendUpdate {
  final String taskId;
  const BackendUpdate(this.taskId);
}

final class BackendProgressUpdate extends BackendUpdate {
  /// 0.0-1.0. background_downloader uses small negative sentinels for
  /// special states (e.g. waiting-to-retry); callers should clamp to 0-1.
  final double progress;
  final int? expectedFileSizeBytes;

  /// Live transfer estimates the plugin exposes on its progress channel.
  /// [networkSpeedMBs] is MB/s, valid only when positive; [timeRemaining]
  /// is valid only when non-negative. Both default to the plugin's
  /// "unknown" sentinels so a caller that doesn't have them (the fake
  /// backend) surfaces nothing rather than a fake estimate.
  final double networkSpeedMBs;
  final Duration timeRemaining;
  const BackendProgressUpdate(
    super.taskId, {
    required this.progress,
    this.expectedFileSizeBytes,
    this.networkSpeedMBs = -1,
    this.timeRemaining = const Duration(seconds: -1),
  });
}

final class BackendStatusUpdate extends BackendUpdate {
  final BackendTaskStatus status;
  final String? errorMessage;
  const BackendStatusUpdate(
    super.taskId, {
    required this.status,
    this.errorMessage,
  });
}

abstract interface class DownloadBackend {
  Stream<BackendUpdate> get updates;

  Future<bool> enqueue(BackendDownloadRequest request);
  Future<bool> pause(String taskId);
  Future<bool> resume(String taskId);
  Future<bool> cancel(String taskId);

  /// Absolute path of the (possibly partial) file for [taskId], or null if
  /// the backend has no record of it.
  Future<String?> filePathFor(String taskId);

  /// Activates the backend's own persistent task tracking (survives app
  /// restart) and returns every task it already knows about — running,
  /// paused, or finished while nothing was listening. Does NOT deliver any
  /// missed updates onto [updates] — see [flushMissedUpdates] for that.
  ///
  /// Call once, before [flushMissedUpdates] and before any `enqueue`.
  /// `DownloadManager.init` (called by the DI provider) does this and
  /// rebuilds its active-task map from the result *before* calling
  /// [flushMissedUpdates] — that ordering is the whole point of splitting
  /// these two steps: a missed completion flushed onto [updates] has to
  /// find an already-rebuilt map, or it's dropped as an unrecognized
  /// taskId (the original app-restart bug, reintroduced as a race if these
  /// were combined into one call with the flush first).
  Future<List<RehydratedTask>> rehydrate();

  /// Delivers status/progress updates that happened while nothing was
  /// listening (app killed/backgrounded) onto [updates]. Call only after
  /// [rehydrate]'s result has been used to rebuild the caller's active-task
  /// map — see [rehydrate]'s doc comment for why the order matters.
  Future<void> flushMissedUpdates();
}
