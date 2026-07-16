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

  const BackendDownloadRequest({
    required this.taskId,
    required this.url,
    required this.fileName,
    required this.directoryPath,
    this.allowPause = true,
  });
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
}
