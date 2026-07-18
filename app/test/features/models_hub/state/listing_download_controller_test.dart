// Phase B D1-D3: download-on-listing enqueues the DEFAULT quant, the tile
// state machine (Download → progress → Installed), and delete-on-listing —
// all driven through a real DownloadManager + FakeDownloadBackend, with the
// HF repo-files/license fetch mocked.

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/features/models_hub/state/download_actions_controller.dart';
import 'package:dhruva/features/models_hub/state/listing_download_controller.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../../support/mock_hf_client.dart';

const _repoId = 'bartowski/Test-1B-Instruct-GGUF';
const _fileName = 'Test-1B-Instruct-Q4_K_M.gguf';
const _taskId = '$_repoId::$_fileName';
const _sizeBytes = 1000;

// QA (Phase B attack #1): a second, independent repo for the "two rows
// downloading at once" cross-talk test.
const _repoId2 = 'bartowski/Test-3B-Instruct-GGUF';
const _fileName2 = 'Test-3B-Instruct-Q4_K_M.gguf';
const _taskId2 = '$_repoId2::$_fileName2';
const _sizeBytes2 = 2000;

// QA (Phase B attack #3): a repo whose file tree reports size 0 — the
// "totalBytes unknown" case a HF response could plausibly return.
const _repoIdUnknownSize = 'bartowski/Test-Unknown-Size-GGUF';
const _fileNameUnknownSize = 'Test-Unknown-Size-Q4_K_M.gguf';
const _taskIdUnknownSize = '$_repoIdUnknownSize::$_fileNameUnknownSize';

// WS1: a vision repo — model GGUF + an mmproj projector — so the one-tap
// listing download must chain BOTH files, not leave a "needs projector"
// half-install.
const _repoIdVision = 'ggml-org/Test-VLM-GGUF';
const _fileNameVision = 'Test-VLM-Q4_K_M.gguf';
const _taskIdVision = '$_repoIdVision::$_fileNameVision';
const _mmprojFileName = 'mmproj-Test-VLM-f16.gguf';
const _mmprojTaskId = '$_repoIdVision::$_mmprojFileName';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

/// Serves the per-repo license + a two-quant file tree so [pickDefaultQuant]
/// resolves the Q4_K_M. Not gated.
http.Response _hfResponder(http.Request request) {
  final path = request.url.path;
  if (path == '/api/models/$_repoId') {
    return http.Response(
      jsonEncode({
        'id': _repoId,
        'gated': false,
        'cardData': {'license': 'apache-2.0'},
      }),
      200,
    );
  }
  if (path == '/api/models/$_repoId/tree/main') {
    return http.Response(
      jsonEncode([
        {'type': 'file', 'path': _fileName, 'size': _sizeBytes},
        {'type': 'file', 'path': 'Test-1B-Instruct-Q8_0.gguf', 'size': 2000},
      ]),
      200,
    );
  }
  // QA: second, independent repo for concurrent-download tests.
  if (path == '/api/models/$_repoId2') {
    return http.Response(
      jsonEncode({
        'id': _repoId2,
        'gated': false,
        'cardData': {'license': 'apache-2.0'},
      }),
      200,
    );
  }
  if (path == '/api/models/$_repoId2/tree/main') {
    return http.Response(
      jsonEncode([
        {'type': 'file', 'path': _fileName2, 'size': _sizeBytes2},
      ]),
      200,
    );
  }
  // QA: a repo whose file-tree entry reports size 0 (totalBytes unknown).
  if (path == '/api/models/$_repoIdUnknownSize') {
    return http.Response(
      jsonEncode({
        'id': _repoIdUnknownSize,
        'gated': false,
        'cardData': {'license': 'apache-2.0'},
      }),
      200,
    );
  }
  if (path == '/api/models/$_repoIdUnknownSize/tree/main') {
    return http.Response(
      jsonEncode([
        {'type': 'file', 'path': _fileNameUnknownSize, 'size': 0},
      ]),
      200,
    );
  }
  // WS1 vision repo: license + a model GGUF paired with an mmproj projector.
  if (path == '/api/models/$_repoIdVision') {
    return http.Response(
      jsonEncode({
        'id': _repoIdVision,
        'gated': false,
        'cardData': {'license': 'apache-2.0'},
      }),
      200,
    );
  }
  if (path == '/api/models/$_repoIdVision/tree/main') {
    return http.Response(
      jsonEncode([
        {'type': 'file', 'path': _fileNameVision, 'size': 1500},
        {'type': 'file', 'path': _mmprojFileName, 'size': 900},
      ]),
      200,
    );
  }
  return http.Response('not found', 404);
}

void main() {
  late AppDatabase db;
  late Directory modelsDir;
  late FakeDownloadBackend backend;
  late DownloadManager manager;
  late ProviderContainer container;

  ProviderContainer build({http.Response Function(http.Request)? responder}) =>
      ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
          downloadManagerProvider.overrideWith((ref) async => manager),
          hfApiClientProvider.overrideWithValue(
            mockHfClient(
              MockClient((r) async => (responder ?? _hfResponder)(r)),
            ),
          ),
        ],
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    modelsDir = Directory.systemTemp.createTempSync('listing_dl_test_');
    backend = FakeDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
    container = build();
  });

  tearDown(() async {
    container.dispose();
    await manager.dispose();
    await db.close();
    if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
  });

  ListingModelState stateFor(String repoId) =>
      container.read(listingDownloadControllerProvider).value?[repoId] ??
      const ListingModelState();

  test('download() resolves + enqueues the DEFAULT (Q4_K_M) quant', () async {
    await container.read(listingDownloadControllerProvider.future);
    await container
        .read(listingDownloadControllerProvider.notifier)
        .download(_repoId);

    // The Q4_K_M was chosen over the larger Q8_0 in the same repo.
    expect(backend.enqueuedRequests.keys, contains(_taskId));
    expect(stateFor(_repoId).status, ListingModelStatus.downloading);
  });

  test('download() on a vision repo chains the mmproj projector', () async {
    await container.read(listingDownloadControllerProvider.future);
    // Instantiate the pairing coordinator so its progress listener attaches
    // before the model completes.
    container.read(downloadActionsControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container
        .read(listingDownloadControllerProvider.notifier)
        .download(_repoIdVision);

    // The model GGUF is enqueued first, and the row reads as downloading.
    expect(backend.enqueuedRequests.keys, contains(_taskIdVision));
    expect(stateFor(_repoIdVision).status, ListingModelStatus.downloading);

    // Completing the model triggers the chained projector download — the fix
    // for the "vision model downloaded without its projector" half-install.
    File(
      '${modelsDir.path}/$_fileNameVision',
    ).writeAsBytesSync(List.filled(1500, 0));
    backend.emit(
      BackendStatusUpdate(_taskIdVision, status: BackendTaskStatus.complete),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(backend.enqueuedRequests.keys, contains(_mmprojTaskId));
  });

  test('tile state machine: Download → progress → Installed', () async {
    await container.read(listingDownloadControllerProvider.future);
    final notifier = container.read(listingDownloadControllerProvider.notifier);

    expect(stateFor(_repoId).status, ListingModelStatus.notInstalled);

    await notifier.download(_repoId);
    expect(stateFor(_repoId).status, ListingModelStatus.downloading);

    // Mid-download progress drives the ring 0..1.
    backend.emit(
      BackendProgressUpdate(
        _taskId,
        progress: 0.5,
        expectedFileSizeBytes: _sizeBytes,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(stateFor(_repoId).status, ListingModelStatus.downloading);
    expect(stateFor(_repoId).progress, closeTo(0.5, 0.001));

    // Completion: the manager verifies the file on disk, registers it, and
    // emits complete → the row flips to Installed with a delete-able id.
    File(
      '${modelsDir.path}/$_fileName',
    ).writeAsBytesSync(List.filled(_sizeBytes, 0));
    backend.emit(
      BackendStatusUpdate(_taskId, status: BackendTaskStatus.complete),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(stateFor(_repoId).status, ListingModelStatus.installed);
    expect(stateFor(_repoId).installedId, isNotNull);
  });

  test('cancel() reverts a downloading row to not-installed', () async {
    await container.read(listingDownloadControllerProvider.future);
    final notifier = container.read(listingDownloadControllerProvider.notifier);
    await notifier.download(_repoId);
    expect(stateFor(_repoId).status, ListingModelStatus.downloading);

    await notifier.cancel(_repoId);
    expect(stateFor(_repoId).status, ListingModelStatus.notInstalled);
    expect(backend.cancelCalls, contains(_taskId));
  });

  test('gated repo cannot be downloaded from the listing', () async {
    container.dispose();
    container = build(
      responder: (request) {
        if (request.url.path == '/api/models/$_repoId') {
          return http.Response(
            jsonEncode({'id': _repoId, 'gated': 'manual'}),
            200,
          );
        }
        return _hfResponder(request);
      },
    );
    await container.read(listingDownloadControllerProvider.future);
    await container
        .read(listingDownloadControllerProvider.notifier)
        .download(_repoId);

    expect(stateFor(_repoId).status, ListingModelStatus.failed);
    expect(backend.enqueuedRequests, isEmpty);
  });

  // WS1: a model too large for the device's RAM is refused at download time —
  // the real per-device guard the search filter's name-only param cap can't
  // provide (a big repo encoding no "B" token slips through). Enqueue never
  // happens, so no multi-GB download lands only to OOM at chat-load.
  test('download() refuses a model too large for this phone\'s RAM', () async {
    const bigRepoId = 'bartowski/Huge-Model-GGUF';
    const bigFileName = 'Huge-Model-Q4_K_M.gguf';
    const gib = 1024 * 1024 * 1024;
    container.dispose();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(
          const FakeDeviceInfoService(
            memory: DeviceMemoryInfo(
              totalBytes: 4 * gib,
              availableBytes: 2 * gib,
            ),
            storage: DeviceStorageInfo(
              totalBytes: 256000000000,
              freeBytes: 200000000000,
            ),
          ),
        ),
        modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
        downloadManagerProvider.overrideWith((ref) async => manager),
        hfApiClientProvider.overrideWithValue(
          mockHfClient(
            MockClient((r) async {
              final path = r.url.path;
              if (path == '/api/models/$bigRepoId') {
                return http.Response(
                  jsonEncode({
                    'id': bigRepoId,
                    'gated': false,
                    'cardData': {'license': 'apache-2.0'},
                  }),
                  200,
                );
              }
              if (path == '/api/models/$bigRepoId/tree/main') {
                return http.Response(
                  jsonEncode([
                    // ~4.7 GiB → 4B+ class, 8 GiB floor, above the 4 GiB phone.
                    {'type': 'file', 'path': bigFileName, 'size': 5000000000},
                  ]),
                  200,
                );
              }
              return http.Response('not found', 404);
            }),
          ),
        ),
      ],
    );

    await container.read(listingDownloadControllerProvider.future);
    await container
        .read(listingDownloadControllerProvider.notifier)
        .download(bigRepoId);

    expect(stateFor(bigRepoId).status, ListingModelStatus.failed);
    expect(stateFor(bigRepoId).errorMessage, contains('RAM'));
    expect(backend.enqueuedRequests, isEmpty);
  });

  test('build() seeds Installed for a model already on disk', () async {
    await db.upsertInstalledModel(
      InstalledModelsCompanion.insert(
        repoId: _repoId,
        fileName: _fileName,
        sizeBytes: _sizeBytes,
        localPath: '${modelsDir.path}/$_fileName',
        downloadedAt: DateTime.now(),
        quant: const Value('Q4_K_M'),
      ),
    );
    File(
      '${modelsDir.path}/$_fileName',
    ).writeAsBytesSync(List.filled(_sizeBytes, 0));

    await container.read(listingDownloadControllerProvider.future);
    expect(stateFor(_repoId).status, ListingModelStatus.installed);
  });

  test('delete() removes an installed model from the listing', () async {
    final id = await db.upsertInstalledModel(
      InstalledModelsCompanion.insert(
        repoId: _repoId,
        fileName: _fileName,
        sizeBytes: _sizeBytes,
        localPath: '${modelsDir.path}/$_fileName',
        downloadedAt: DateTime.now(),
      ),
    );
    File(
      '${modelsDir.path}/$_fileName',
    ).writeAsBytesSync(List.filled(_sizeBytes, 0));

    await container.read(listingDownloadControllerProvider.future);
    expect(stateFor(_repoId).installedId, id);

    await container
        .read(listingDownloadControllerProvider.notifier)
        .delete(_repoId);

    expect(stateFor(_repoId).status, ListingModelStatus.notInstalled);
    expect(File('${modelsDir.path}/$_fileName').existsSync(), isFalse);
    expect(await db.select(db.installedModels).get(), isEmpty);
  });

  // QA (Phase B attack #1): two search rows downloading at once. The
  // controller's map is keyed by repoId (`_set`/`_onProgress` in
  // listing_download_controller.dart) — this proves progress for one repo
  // never leaks into the other's entry.
  test(
    'two repos downloading concurrently: independent progress, no cross-talk',
    () async {
      await container.read(listingDownloadControllerProvider.future);
      final notifier = container.read(
        listingDownloadControllerProvider.notifier,
      );

      await notifier.download(_repoId);
      await notifier.download(_repoId2);
      expect(stateFor(_repoId).status, ListingModelStatus.downloading);
      expect(stateFor(_repoId2).status, ListingModelStatus.downloading);
      // Distinct taskIds — the enqueue for repo 2 didn't touch repo 1's row.
      expect(backend.enqueuedRequests.keys, containsAll([_taskId, _taskId2]));

      backend.emit(
        BackendProgressUpdate(
          _taskId,
          progress: 0.9,
          expectedFileSizeBytes: _sizeBytes,
        ),
      );
      backend.emit(
        BackendProgressUpdate(
          _taskId2,
          progress: 0.1,
          expectedFileSizeBytes: _sizeBytes2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(stateFor(_repoId).progress, closeTo(0.9, 0.001));
      expect(stateFor(_repoId2).progress, closeTo(0.1, 0.001));

      // Completing repo 1 must not disturb repo 2's still-downloading state.
      File(
        '${modelsDir.path}/$_fileName',
      ).writeAsBytesSync(List.filled(_sizeBytes, 0));
      backend.emit(
        BackendStatusUpdate(_taskId, status: BackendTaskStatus.complete),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(stateFor(_repoId).status, ListingModelStatus.installed);
      expect(stateFor(_repoId2).status, ListingModelStatus.downloading);
      expect(stateFor(_repoId2).progress, closeTo(0.1, 0.001));

      // Cancelling repo 2 afterwards must not touch repo 1's now-installed row.
      await notifier.cancel(_repoId2);
      expect(stateFor(_repoId2).status, ListingModelStatus.notInstalled);
      expect(stateFor(_repoId).status, ListingModelStatus.installed);
    },
  );

  // QA (Phase B attack #3): progress ring math — totalBytes 0/unknown must
  // never divide by zero and must fall back to 0.0 (rendered as an
  // indeterminate ring by ModelListTile: `value: progress == 0 ? null : ...`).
  test('totalBytes 0/unknown: progress stays 0.0, no divide-by-zero', () async {
    await container.read(listingDownloadControllerProvider.future);
    final notifier = container.read(listingDownloadControllerProvider.notifier);
    await notifier.download(_repoIdUnknownSize);
    expect(stateFor(_repoIdUnknownSize).status, ListingModelStatus.downloading);

    // No expectedFileSizeBytes on the wire AND the resolved quant's own
    // size was 0 (request.expectedSizeBytes backfill is also 0) — the
    // real "HF reported a 0-byte file" case.
    backend.emit(BackendProgressUpdate(_taskIdUnknownSize, progress: 0.5));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final state = stateFor(_repoIdUnknownSize);
    expect(state.status, ListingModelStatus.downloading);
    expect(state.progress, 0.0);
  });

  // QA (Phase B attack #3): backwards progress (a resumed/retried segment
  // reporting a lower fraction than it previously did) is just reflected as
  // received — no monotonic clamp exists, and none is needed: the ring is a
  // live mirror of the backend's own state, not an accumulator.
  test(
    'progress can move backwards; the ring just reflects the latest tick',
    () async {
      await container.read(listingDownloadControllerProvider.future);
      final notifier = container.read(
        listingDownloadControllerProvider.notifier,
      );
      await notifier.download(_repoId);

      backend.emit(
        BackendProgressUpdate(
          _taskId,
          progress: 0.7,
          expectedFileSizeBytes: _sizeBytes,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(stateFor(_repoId).progress, closeTo(0.7, 0.001));

      backend.emit(
        BackendProgressUpdate(
          _taskId,
          progress: 0.3,
          expectedFileSizeBytes: _sizeBytes,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(stateFor(_repoId).progress, closeTo(0.3, 0.001));
    },
  );

  // QA (Phase B attack #1): cancel mid-progress cleans up the partial file
  // on disk (DownloadManager._cleanupPartialFile, exercised end-to-end
  // through the listing controller's cancel()).
  test('cancel mid-progress deletes the partial file from disk', () async {
    await container.read(listingDownloadControllerProvider.future);
    final notifier = container.read(listingDownloadControllerProvider.notifier);
    await notifier.download(_repoId);

    final partial = File('${modelsDir.path}/$_fileName')
      ..writeAsBytesSync(List.filled(400, 0)); // partial write, not complete
    backend.filePaths[_taskId] = partial.path;
    backend.emit(
      BackendProgressUpdate(
        _taskId,
        progress: 0.4,
        expectedFileSizeBytes: _sizeBytes,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(partial.existsSync(), isTrue);

    await notifier.cancel(_repoId);

    expect(stateFor(_repoId).status, ListingModelStatus.notInstalled);
    expect(partial.existsSync(), isFalse);
  });
}
