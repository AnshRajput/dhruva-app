// WS2: onboarding state — the "shown once" sentinel store, the
// device-appropriate recommended pick, and the single-model download
// controller that drives the guided pick → download → ready step (a real
// DownloadManager + FakeDownloadBackend, with the HF fetch mocked, same shape
// as listing_download_controller_test).

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/device_info/model_tier.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/data/models/starter_catalog.dart';
import 'package:dhruva/features/onboarding/state/onboarding_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../../support/mock_hf_client.dart';

const _repoId = 'bartowski/Onboard-1B-Instruct-GGUF';
const _fileName = 'Onboard-1B-Instruct-Q4_K_M.gguf';
const _taskId = '$_repoId::$_fileName';
const _sizeBytes = 1000;

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
        {'type': 'file', 'path': 'Onboard-1B-Instruct-Q8_0.gguf', 'size': 2000},
      ]),
      200,
    );
  }
  return http.Response('not found', 404);
}

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  group('FileOnboardingStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('onboard_store_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test(
      'is not complete until marked, then persists across instances',
      () async {
        final store = FileOnboardingStore(dir);
        expect(await store.isComplete(), isFalse);

        await store.markComplete();
        expect(await store.isComplete(), isTrue);

        // A fresh store over the same dir (a later app launch) still sees it —
        // this is the "shown once" guarantee.
        expect(await FileOnboardingStore(dir).isComplete(), isTrue);
      },
    );

    test('markComplete is idempotent', () async {
      final store = FileOnboardingStore(dir);
      await store.markComplete();
      await store.markComplete();
      expect(await store.isComplete(), isTrue);
    });
  });

  group('recommendedStarterModel', () {
    test('is never a vision model', () {
      for (final ram in [null, 2000000000, 8000000000, 34359738368]) {
        expect(recommendedStarterModel(ram).isVision, isFalse);
      }
    });

    test('unknown RAM falls back to the smallest (always-runnable) model', () {
      final smallestText = starterModelCatalog.firstWhere((m) => !m.isVision);
      expect(recommendedStarterModel(null).repoId, smallestText.repoId);
    });

    test('a tiny device gets the smallest model, never a dead-end', () {
      // 2 GiB: below every catalog model's floor → not-recommended across the
      // board → the smallest, most-runnable pick rather than nothing.
      final rec = recommendedStarterModel(2 * 1024 * 1024 * 1024);
      final smallestText = starterModelCatalog.firstWhere((m) => !m.isVision);
      expect(rec.repoId, smallestText.repoId);
    });

    test('a typical 8GB phone gets a model that runs comfortably', () {
      const ram = 8000000000;
      final rec = recommendedStarterModel(ram);
      expect(
        classifyModelTier(
          fileSizeBytes: rec.approxSizeBytes,
          totalRamBytes: ram,
        ),
        ModelTier.comfortable,
      );
    });

    test('a large-RAM device gets the most capable (largest) text model', () {
      const ram = 34359738368; // 32 GiB — everything is comfortable.
      final largestText = starterModelCatalog
          .where((m) => !m.isVision)
          .reduce((a, b) => a.approxSizeBytes >= b.approxSizeBytes ? a : b);
      expect(recommendedStarterModel(ram).repoId, largestText.repoId);
    });
  });

  group('OnboardingDownloadController', () {
    late AppDatabase db;
    late Directory modelsDir;
    late FakeDownloadBackend backend;
    late DownloadManager manager;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      modelsDir = Directory.systemTemp.createTempSync('onboard_dl_');
      backend = FakeDownloadBackend();
      manager = DownloadManager(
        backend: backend,
        db: db,
        modelsDirectory: modelsDir,
      );
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
          downloadManagerProvider.overrideWith((ref) async => manager),
          hfApiClientProvider.overrideWithValue(
            mockHfClient(MockClient((r) async => _hfResponder(r))),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await manager.dispose();
      await db.close();
      if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
    });

    OnboardingDownloadState stateNow() =>
        container.read(onboardingDownloadControllerProvider).value ??
        const OnboardingDownloadState();

    test(
      'download → progress → installed with a chat-ready model id',
      () async {
        await container.read(onboardingDownloadControllerProvider.future);
        final notifier = container.read(
          onboardingDownloadControllerProvider.notifier,
        );

        await notifier.download(_repoId);
        // The Q4_K_M was chosen over the larger Q8_0.
        expect(backend.enqueuedRequests.keys, contains(_taskId));
        expect(stateNow().status, OnboardingDownloadStatus.downloading);

        backend.emit(
          BackendProgressUpdate(
            _taskId,
            progress: 0.5,
            expectedFileSizeBytes: _sizeBytes,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(stateNow().progress, closeTo(0.5, 0.001));
        // The live DownloadProgress is carried so the step can show real
        // bytes (speed/ETA absent here — the fake backend emits none).
        expect(stateNow().download?.transferLabel, '500 B / 1000 B');

        File(
          '${modelsDir.path}/$_fileName',
        ).writeAsBytesSync(List.filled(_sizeBytes, 0));
        backend.emit(
          BackendStatusUpdate(_taskId, status: BackendTaskStatus.complete),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(stateNow().status, OnboardingDownloadStatus.installed);
        // The success step needs a real drift row id to open a loaded chat.
        expect(stateNow().installedId, isNotNull);
      },
    );

    test('cancel stops the in-flight download and resets to idle', () async {
      await container.read(onboardingDownloadControllerProvider.future);
      final notifier = container.read(
        onboardingDownloadControllerProvider.notifier,
      );

      await notifier.download(_repoId);
      expect(stateNow().status, OnboardingDownloadStatus.downloading);

      await notifier.cancel();
      // The manager was actually told to cancel this task, and the step is
      // back to a clean idle (the download step's Cancel / Android back is not
      // a dead-end).
      expect(backend.cancelCalls, contains(_taskId));
      expect(stateNow().status, OnboardingDownloadStatus.idle);
    });

    test(
      'cancel during resolve never starts an orphaned background download',
      () async {
        await container.read(onboardingDownloadControllerProvider.future);
        final notifier = container.read(
          onboardingDownloadControllerProvider.notifier,
        );

        // Kick off the download but cancel while it is still resolving the
        // quant (before enqueue). The in-flight resolve must bail rather than
        // start a real download the user believes they cancelled.
        final downloading = notifier.download(_repoId);
        await notifier.cancel();
        await downloading;

        expect(backend.enqueuedRequests, isEmpty);
        expect(stateNow().status, OnboardingDownloadStatus.idle);
      },
    );

    test(
      'a too-big-for-RAM model warns before download, then force downloads',
      () async {
        // A sub-4GB phone: the 1000-byte file classifies notRecommended
        // (1B-class floor is 4GB). Onboarding must NOT silently enqueue it —
        // that is the OOM-at-chat-load path the hub already guards.
        container.dispose();
        container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            deviceInfoServiceProvider.overrideWithValue(
              const FakeDeviceInfoService(
                memory: DeviceMemoryInfo(
                  totalBytes: 3000000000, // ~2.8 GiB, below the 4GB floor
                  availableBytes: 1500000000,
                ),
                storage: DeviceStorageInfo(
                  totalBytes: 64000000000,
                  freeBytes: 32000000000,
                ),
              ),
            ),
            modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
            downloadManagerProvider.overrideWith((ref) async => manager),
            hfApiClientProvider.overrideWithValue(
              mockHfClient(MockClient((r) async => _hfResponder(r))),
            ),
          ],
        );
        await container.read(onboardingDownloadControllerProvider.future);
        final notifier = container.read(
          onboardingDownloadControllerProvider.notifier,
        );

        await notifier.download(_repoId);
        expect(stateNow().status, OnboardingDownloadStatus.oversizeWarning);
        expect(stateNow().errorMessage, isNotNull);
        expect(backend.enqueuedRequests, isEmpty);

        // "Download anyway" bypasses the guard — never a dead-end.
        await notifier.download(_repoId, force: true);
        expect(stateNow().status, OnboardingDownloadStatus.downloading);
        expect(backend.enqueuedRequests.keys, contains(_taskId));
      },
    );

    test('a gated model fails gracefully instead of dead-ending', () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
          downloadManagerProvider.overrideWith((ref) async => manager),
          hfApiClientProvider.overrideWithValue(
            mockHfClient(
              MockClient((request) async {
                if (request.url.path == '/api/models/$_repoId') {
                  return http.Response(
                    jsonEncode({'id': _repoId, 'gated': 'manual'}),
                    200,
                  );
                }
                return _hfResponder(request);
              }),
            ),
          ),
        ],
      );
      await container.read(onboardingDownloadControllerProvider.future);
      await container
          .read(onboardingDownloadControllerProvider.notifier)
          .download(_repoId);

      expect(stateNow().status, OnboardingDownloadStatus.failed);
      expect(stateNow().errorMessage, isNotNull);
      expect(backend.enqueuedRequests, isEmpty);
    });
  });
}
