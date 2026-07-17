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
  const BackendProgressUpdate(
    super.taskId, {
    required this.progress,
    this.expectedFileSizeBytes,
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
  /// paused, or finished while nothing was listening. Must be called once,
  /// after `updates` is being listened to and before any `enqueue`
  /// (`DownloadManager.init`, called by the DI provider, does this) so a
  /// completion that arrives on `updates` as a side effect of this call
  /// lands on an already-rebuilt active-task map instead of being dropped
  /// as an unrecognized taskId.
  Future<List<RehydratedTask>> rehydrate();
}
