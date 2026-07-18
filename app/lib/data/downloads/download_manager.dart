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

  /// The typed failure behind [errorMessage], when [state] is
  /// [DownloadState.failed]. Async failures (backend status updates,
  /// integrity checks) used to only ever surface a raw string here — this
  /// keeps them in the ADR-002 taxonomy so the UI can use
  /// `friendlyFailureMessage`/recovery-affordance logic instead of just
  /// displaying text. `notFound` is typed as an HTTP 404
  /// ([NetworkHttpFailure]) because that's background_downloader's own
  /// documented meaning for that status; a generic `failed` status has no
  /// further detail available without deeper plugin-exception mapping (that
  /// would touch the untested native adapter — left for a later loop), so
  /// it's [NetworkUnknownFailure] rather than left untyped.
  final AppFailure? failure;

  /// Live transfer estimate from the backend's progress channel, only ever
  /// set on a `running` update. [networkSpeedMBs] is MB/s (valid when > 0);
  /// [timeRemaining] is valid when non-negative. Defaults are the "unknown"
  /// sentinels — see [etaLabel], which shows nothing rather than a fake
  /// estimate when they're unknown.
  final double networkSpeedMBs;
  final Duration timeRemaining;

  /// Mirrors [DownloadRequest.registerAsInstalledModel]: false for a vision
  /// model's mmproj projector, which rides the same pipeline but never becomes
  /// its own installed model. The UI uses this to keep the projector out of
  /// the "Ready — start chatting" surfaces (it has no chat-loadable row) — see
  /// `_ReadySection` and `AppShell`'s completion listener.
  final bool registerAsInstalledModel;

  const DownloadProgress({
    required this.taskId,
    required this.repoId,
    required this.fileName,
    required this.state,
    required this.downloadedBytes,
    this.totalBytes,
    this.errorMessage,
    this.failure,
    this.networkSpeedMBs = -1,
    this.timeRemaining = const Duration(seconds: -1),
    this.registerAsInstalledModel = true,
  });

  /// A compact "3.1 MB/s · 0:45 left" line, or null when neither estimate is
  /// known yet — so the UI renders nothing rather than "--:-- left". Speed and
  /// ETA are shown independently: whichever the backend has.
  String? get etaLabel {
    final parts = <String>[];
    if (networkSpeedMBs > 0) {
      parts.add(
        networkSpeedMBs >= 1
            ? '${networkSpeedMBs.toStringAsFixed(1)} MB/s'
            : '${(networkSpeedMBs * 1000).round()} kB/s',
      );
    }
    if (!timeRemaining.isNegative && timeRemaining.inSeconds > 0) {
      final m = timeRemaining.inMinutes;
      final sec = timeRemaining.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      parts.add('$m:$sec left');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Everything needed to enqueue + later verify + register one file download.
final class DownloadRequest {
  final String repoId;
  final String fileName;

  /// The remote resolve URL. Only used to tell the backend where to fetch
  /// from at [DownloadManager.enqueue] time — null for a [DownloadRequest]
  /// rehydrated from [DownloadBackend.rehydrate] after an app restart,
  /// which never goes through `enqueue` again (the OS-level task is already
  /// running/finished; rehydration only needs enough to verify + register
  /// it, see [_encodeMetaData]/[_decodeMetaData]).
  final Uri? url;
  final int expectedSizeBytes;
  final String? expectedSha256;
  final String? quant;
  final String? license;
  final bool gated;

  /// True when this is a vision model's own GGUF (not its projector) —
  /// recorded on the `installed_models` row as `isVision` so a paired-but-
  /// not-yet-downloaded projector reads as a "needs projector" half-state
  /// rather than an indistinguishable plain text model. See
  /// `database.dart`'s `InstalledModels.isVision` doc and
  /// `download_actions_controller.dart`'s `enqueueVisionQuant`.
  final bool isVision;

  /// False for a vision model's mmproj projector download: the file is
  /// still verified + kept on disk by the normal flow below, but it does
  /// NOT get its own `installed_models` row — its path is patched onto the
  /// paired model's row instead (`StorageManager.attachProjector`), so a
  /// vision model is exactly one row, not two. True (default) for every
  /// other caller.
  final bool registerAsInstalledModel;

  const DownloadRequest({
    required this.repoId,
    required this.fileName,
    required this.url,
    required this.expectedSizeBytes,
    this.expectedSha256,
    this.quant,
    this.license,
    this.gated = false,
    this.isVision = false,
    this.registerAsInstalledModel = true,
  });

  /// Stable per repo+file — re-enqueuing the same file reuses the id so a
  /// retry/resume finds the same backend task.
  String get taskId => '$repoId::$fileName';

  /// Serialized into the backend task's opaque `metaData` string at enqueue
  /// time, so [DownloadManager.init] can reconstruct this request after an
  /// app restart from [DownloadBackend.rehydrate] — `url` is deliberately
  /// omitted (see its doc comment); everything `_completeDownload` and the
  /// drift row need is here.
  String _encodeMetaData() => jsonEncode({
    'repoId': repoId,
    'fileName': fileName,
    'expectedSizeBytes': expectedSizeBytes,
    if (expectedSha256 != null) 'sha256': expectedSha256,
    if (quant != null) 'quant': quant,
    if (license != null) 'license': license,
    'gated': gated,
    'isVision': isVision,
    'registerAsInstalledModel': registerAsInstalledModel,
  });

  /// The inverse of [_encodeMetaData]. Returns null (skip this rehydrated
  /// task) rather than throwing on metaData that doesn't parse — e.g. an
  /// empty string from a task this backend didn't create, or a future
  /// format change; a task DownloadManager can't reconstruct falls back to
  /// the existing "unrecognized taskId" drop, same as today.
  static DownloadRequest? _decodeMetaData(String metaData) {
    try {
      final json = jsonDecode(metaData) as Map<String, dynamic>;
      return DownloadRequest(
        repoId: json['repoId'] as String,
        fileName: json['fileName'] as String,
        url: null,
        expectedSizeBytes: json['expectedSizeBytes'] as int,
        expectedSha256: json['sha256'] as String?,
        quant: json['quant'] as String?,
        license: json['license'] as String?,
        gated: json['gated'] as bool? ?? false,
        isVision: json['isVision'] as bool? ?? false,
        registerAsInstalledModel:
            json['registerAsInstalledModel'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }
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

  /// Rebuilds in-memory active-task tracking from the backend's own
  /// persisted state. `_active` normally only gains an entry inside
  /// `enqueue`, so a task that finished (or is still running) from a
  /// *previous* app process — the plugin's own persistent tracking survives
  /// that even though this Dart object graph doesn't — would otherwise
  /// arrive on `updates` with a taskId `_handleUpdate` doesn't recognize and
  /// get silently dropped: an orphan file on disk, never integrity-checked,
  /// never registered in drift, invisible to the Loop-4 model picker.
  ///
  /// Ordering matters here: `_active` is fully rebuilt from
  /// `_backend.rehydrate()` BEFORE `_backend.flushMissedUpdates()` runs.
  /// `flushMissedUpdates` is what actually delivers a missed completion
  /// onto `updates`; calling it before `_active` is populated reintroduces
  /// the exact bug this method exists to fix, just as a race instead of a
  /// guarantee (rehydrate's own `await database.allRecords()` yields to the
  /// event loop, so a flush-then-rebuild ordering can let a flushed update
  /// reach `_handleUpdate` while `_active` is still empty).
  ///
  /// Call once, right after constructing this manager and before any
  /// `enqueue` — `downloadManagerProvider` does this.
  Future<void> init() async {
    final rehydrated = await _backend.rehydrate();
    for (final task in rehydrated) {
      final request = DownloadRequest._decodeMetaData(task.metaData);
      if (request == null) continue;
      _active[task.taskId] = request;
    }
    await _backend.flushMissedUpdates();
  }

  /// Enqueues [request]. Throws [ValidationFailure] if `request.fileName`
  /// doesn't sanitize to a usable local file name (see
  /// `sanitizeLocalFileName` — this is the trust boundary: a subfolder HF
  /// path like `"mmproj/x.gguf"` is flattened, a traversal/garbage name is
  /// rejected outright). Throws [StorageInsufficientSpaceFailure] if
  /// [freeBytes] doesn't leave enough headroom for the file — call this with
  /// a fresh `DeviceStorageInfo.freeBytes` reading from `DeviceInfoService`.
  Future<void> enqueue(
    DownloadRequest request, {
    required int freeBytes,
  }) async {
    final url = request.url;
    if (url == null) {
      // Only a rehydrated (post-restart) DownloadRequest has a null url,
      // and those never go through enqueue — the OS-level task already
      // exists. A caller passing one here is a programming error, not a
      // runtime condition to recover from.
      throw ValidationFailure(
        'DownloadRequest.url is null — this looks like a rehydrated '
        'request being re-enqueued instead of left for init() to track',
      );
    }
    final safeFileName = sanitizeLocalFileName(request.fileName);
    if (safeFileName == null) {
      throw ValidationFailure(
        'invalid download fileName: "${request.fileName}"',
      );
    }
    // The remote resolve URL (`request.url`) is a separate field, built by
    // the caller from the original (possibly subfoldered) HF path — it is
    // deliberately NOT derived from `safeFileName` and is left untouched.
    final safeRequest = safeFileName == request.fileName
        ? request
        : DownloadRequest(
            repoId: request.repoId,
            fileName: safeFileName,
            url: url,
            expectedSizeBytes: request.expectedSizeBytes,
            expectedSha256: request.expectedSha256,
            quant: request.quant,
            license: request.license,
            gated: request.gated,
            isVision: request.isVision,
            registerAsInstalledModel: request.registerAsInstalledModel,
          );

    final guardFailure = checkStorageGuard(
      requiredBytes: safeRequest.expectedSizeBytes,
      freeBytes: freeBytes,
    );
    if (guardFailure != null) throw guardFailure;

    _active[safeRequest.taskId] = safeRequest;
    final enqueued = await _backend.enqueue(
      BackendDownloadRequest(
        taskId: safeRequest.taskId,
        url: url,
        fileName: safeRequest.fileName,
        directoryPath: modelsDirectory.path,
        metaData: safeRequest._encodeMetaData(),
      ),
    );
    if (!enqueued) {
      _active.remove(safeRequest.taskId);
      throw const StorageIoFailure('failed to enqueue download');
    }
    _emit(safeRequest, DownloadState.queued, downloadedBytes: 0);
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
          networkSpeedMBs: u.networkSpeedMBs,
          timeRemaining: u.timeRemaining,
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
        final message = update.errorMessage ?? 'download failed';
        // notFound is background_downloader's documented status for an
        // HTTP 404; a bare `failed` carries no further detail without
        // mapping the plugin's TaskException subtypes (untested native
        // adapter — deferred), so it lands in the last-resort bucket.
        final failure = update.status == BackendTaskStatus.notFound
            ? NetworkHttpFailure(message, statusCode: 404)
            : NetworkUnknownFailure(message);
        _emit(
          request,
          DownloadState.failed,
          downloadedBytes: 0,
          errorMessage: message,
          failure: failure,
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
      const missingFileFailure = StorageNotFoundFailure(
        'downloaded file is missing on disk',
      );
      _emit(
        request,
        DownloadState.failed,
        downloadedBytes: 0,
        errorMessage: missingFileFailure.message,
        failure: missingFileFailure,
      );
      return;
    }

    final actualSize = file.lengthSync();
    String? actualSha256;
    if (request.expectedSha256 != null) {
      try {
        actualSha256 = await streamingSha256(file);
      } on StorageIoFailure catch (readFailure) {
        await _safeDelete(file);
        _active.remove(request.taskId);
        _emit(
          request,
          DownloadState.failed,
          downloadedBytes: 0,
          errorMessage: readFailure.message,
          failure: readFailure,
        );
        return;
      }
    }
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
        failure: integrityFailure,
      );
      return;
    }

    // A vision projector's own download (`registerAsInstalledModel: false`)
    // is verified + kept on disk above like any other file, but doesn't get
    // its own row here — see the field's doc comment and
    // `StorageManager.attachProjector`, which patches its path onto the
    // paired model's row once both are known.
    if (request.registerAsInstalledModel) {
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
          isVision: Value(request.isVision),
          downloadedAt: DateTime.now(),
        ),
      );
    }

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
    AppFailure? failure,
    double networkSpeedMBs = -1,
    Duration timeRemaining = const Duration(seconds: -1),
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
        failure: failure,
        networkSpeedMBs: networkSpeedMBs,
        timeRemaining: timeRemaining,
        registerAsInstalledModel: request.registerAsInstalledModel,
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
///
/// Throws [StorageIoFailure] (not a raw [FileSystemException]) if the file
/// can't be read partway through — a corrupted/permission-denied file
/// mid-stream, not just at open time.
Future<String> streamingSha256(File file) async {
  Digest? digest;
  final sink = ChunkedConversionSink<Digest>.withCallback(
    (digests) => digest = digests.single,
  );
  final input = sha256.startChunkedConversion(sink);
  try {
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
  } on FileSystemException catch (e) {
    throw StorageIoFailure(
      'failed to read ${file.path} while computing checksum',
      cause: e,
    );
  } finally {
    input.close();
  }
  return digest!.toString();
}
