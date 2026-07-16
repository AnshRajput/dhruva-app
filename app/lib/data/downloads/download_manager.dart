import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../core/failures/app_failure.dart';
import '../db/database.dart';
import 'download_backend.dart';
import 'download_core.dart';

enum DownloadState {
  queued,
  running,
  paused,
  verifying,
  complete,
  failed,
  canceled,
}

final class DownloadProgress {
  final String taskId;
  final String repoId;
  final String fileName;
  final DownloadState state;
  final int downloadedBytes;
  final int? totalBytes;
  final String? errorMessage;

  const DownloadProgress({
    required this.taskId,
    required this.repoId,
    required this.fileName,
    required this.state,
    required this.downloadedBytes,
    this.totalBytes,
    this.errorMessage,
  });
}

/// Everything needed to enqueue + later verify + register one file download.
final class DownloadRequest {
  final String repoId;
  final String fileName;
  final Uri url;
  final int expectedSizeBytes;
  final String? expectedSha256;
  final String? quant;
  final String? license;
  final bool gated;

  const DownloadRequest({
    required this.repoId,
    required this.fileName,
    required this.url,
    required this.expectedSizeBytes,
    this.expectedSha256,
    this.quant,
    this.license,
    this.gated = false,
  });

  /// Stable per repo+file — re-enqueuing the same file reuses the id so a
  /// retry/resume finds the same backend task.
  String get taskId => '$repoId::$fileName';
}

/// Orchestrates downloads over a [DownloadBackend] (real:
/// `BackgroundDownloaderBackend`, test: a fake), verifying integrity with
/// `download_core.dart` and registering completed files into [AppDatabase].
/// This is the surface `features/models_hub` should consume — it never
/// imports `background_downloader` directly.
final class DownloadManager {
  final DownloadBackend _backend;
  final AppDatabase _db;

  /// Absolute directory downloads are written into. Callers (DI wiring)
  /// resolve this once via `path_provider` at app startup.
  final Directory modelsDirectory;

  final _controller = StreamController<DownloadProgress>.broadcast();
  final Map<String, DownloadRequest> _active = {};
  late final StreamSubscription<BackendUpdate> _subscription;

  DownloadManager({
    required DownloadBackend backend,
    required AppDatabase db,
    required this.modelsDirectory,
  }) : _backend = backend,
       _db = db {
    _subscription = _backend.updates.listen(_handleUpdate);
  }

  Stream<DownloadProgress> get progress => _controller.stream;

  /// Enqueues [request]. Throws [StorageInsufficientSpaceFailure] if
  /// [freeBytes] doesn't leave enough headroom for the file — call this with
  /// a fresh `DeviceStorageInfo.freeBytes` reading from `DeviceInfoService`.
  Future<void> enqueue(
    DownloadRequest request, {
    required int freeBytes,
  }) async {
    final guardFailure = checkStorageGuard(
      requiredBytes: request.expectedSizeBytes,
      freeBytes: freeBytes,
    );
    if (guardFailure != null) throw guardFailure;

    _active[request.taskId] = request;
    final enqueued = await _backend.enqueue(
      BackendDownloadRequest(
        taskId: request.taskId,
        url: request.url,
        fileName: request.fileName,
        directoryPath: modelsDirectory.path,
      ),
    );
    if (!enqueued) {
      _active.remove(request.taskId);
      throw const StorageIoFailure('failed to enqueue download');
    }
    _emit(request, DownloadState.queued, downloadedBytes: 0);
  }

  Future<void> pause(String taskId) => _backend.pause(taskId);

  Future<void> resume(String taskId) => _backend.resume(taskId);

  /// Cancels the task and deletes any partial file on disk.
  Future<void> cancel(String taskId) async {
    await _backend.cancel(taskId);
    await _cleanupPartialFile(taskId);
    final request = _active.remove(taskId);
    if (request != null) {
      _emit(request, DownloadState.canceled, downloadedBytes: 0);
    }
  }

  Future<void> _handleUpdate(BackendUpdate update) async {
    final request = _active[update.taskId];
    if (request == null) return;
    switch (update) {
      case final BackendProgressUpdate u:
        // background_downloader uses negative sentinels (failed/canceled/
        // notFound/waitingToRetry) on the progress channel; the paired
        // status update on the other channel carries the real transition,
        // so sentinels here are ignored rather than misread as 0%.
        if (u.progress < 0) return;
        final total = u.expectedFileSizeBytes ?? request.expectedSizeBytes;
        _emit(
          request,
          DownloadState.running,
          downloadedBytes: (u.progress.clamp(0, 1) * total).round(),
          totalBytes: total,
        );
      case final BackendStatusUpdate u:
        await _handleStatus(request, u);
    }
  }

  Future<void> _handleStatus(
    DownloadRequest request,
    BackendStatusUpdate update,
  ) async {
    switch (update.status) {
      case BackendTaskStatus.enqueued:
        _emit(request, DownloadState.queued, downloadedBytes: 0);
      case BackendTaskStatus.running:
        _emit(request, DownloadState.running, downloadedBytes: 0);
      case BackendTaskStatus.paused:
        _emit(request, DownloadState.paused, downloadedBytes: 0);
      case BackendTaskStatus.complete:
        await _completeDownload(request);
      case BackendTaskStatus.failed:
      case BackendTaskStatus.notFound:
        await _cleanupPartialFile(request.taskId);
        _active.remove(request.taskId);
        _emit(
          request,
          DownloadState.failed,
          downloadedBytes: 0,
          errorMessage: update.errorMessage ?? 'download failed',
        );
      case BackendTaskStatus.canceled:
        _active.remove(request.taskId);
        _emit(request, DownloadState.canceled, downloadedBytes: 0);
    }
  }

  Future<void> _completeDownload(DownloadRequest request) async {
    _emit(
      request,
      DownloadState.verifying,
      downloadedBytes: request.expectedSizeBytes,
      totalBytes: request.expectedSizeBytes,
    );

    final path =
        await _backend.filePathFor(request.taskId) ??
        p.join(modelsDirectory.path, request.fileName);
    final file = File(path);
    if (!file.existsSync()) {
      _active.remove(request.taskId);
      _emit(
        request,
        DownloadState.failed,
        downloadedBytes: 0,
        errorMessage: 'downloaded file is missing on disk',
      );
      return;
    }

    final actualSize = file.lengthSync();
    final actualSha256 = request.expectedSha256 != null
        ? await streamingSha256(file)
        : null;
    final integrityFailure = verifyIntegrity(
      expectedSizeBytes: request.expectedSizeBytes,
      actualSizeBytes: actualSize,
      expectedSha256: request.expectedSha256,
      actualSha256: actualSha256,
    );
    if (integrityFailure != null) {
      await _safeDelete(file);
      _active.remove(request.taskId);
      _emit(
        request,
        DownloadState.failed,
        downloadedBytes: 0,
        errorMessage: integrityFailure.message,
      );
      return;
    }

    await _db.upsertInstalledModel(
      InstalledModelsCompanion.insert(
        repoId: request.repoId,
        fileName: request.fileName,
        quant: Value(request.quant),
        sizeBytes: actualSize,
        sha256: Value(request.expectedSha256),
        localPath: path,
        license: Value(request.license),
        gated: Value(request.gated),
        downloadedAt: DateTime.now(),
      ),
    );

    _active.remove(request.taskId);
    _emit(
      request,
      DownloadState.complete,
      downloadedBytes: actualSize,
      totalBytes: actualSize,
    );
  }

  Future<void> _cleanupPartialFile(String taskId) async {
    final path = await _backend.filePathFor(taskId);
    if (path == null) return;
    await _safeDelete(File(path));
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Best-effort cleanup; a leftover partial file is a disk-space nit,
      // not a correctness problem — it never gets a drift row.
    }
  }

  void _emit(
    DownloadRequest request,
    DownloadState state, {
    required int downloadedBytes,
    int? totalBytes,
    String? errorMessage,
  }) {
    _controller.add(
      DownloadProgress(
        taskId: request.taskId,
        repoId: request.repoId,
        fileName: request.fileName,
        state: state,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes ?? request.expectedSizeBytes,
        errorMessage: errorMessage,
      ),
    );
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }
}

/// Streams [file] through sha256 in chunks rather than loading a
/// multi-gigabyte GGUF fully into memory — this app's own device floor
/// (DECISIONS.md) starts at 4GB total RAM, so a whole-file read here would
/// risk OOMing the exact devices it needs to run on.
Future<String> streamingSha256(File file) async {
  Digest? digest;
  final sink = ChunkedConversionSink<Digest>.withCallback(
    (digests) => digest = digests.single,
  );
  final input = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return digest!.toString();
}
