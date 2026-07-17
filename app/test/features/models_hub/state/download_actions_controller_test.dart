import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/features/models_hub/state/download_actions_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory modelsDir;
  late FakeDownloadBackend backend;
  late DownloadManager manager;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    modelsDir = Directory.systemTemp.createTempSync('dhruva_actions_test_');
    backend = FakeDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
    container = ProviderContainer(
      overrides: [
        downloadManagerProvider.overrideWith((ref) async => manager),
        deviceInfoServiceProvider.overrideWithValue(
          const FakeDeviceInfoService(
            memory: DeviceMemoryInfo(
              totalBytes: 8000000000,
              availableBytes: 4000000000,
            ),
            storage: DeviceStorageInfo(
              totalBytes: 64000000000,
              freeBytes: 32000000000,
            ),
          ),
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

  DownloadRequest req({int expectedSizeBytes = 1000}) => DownloadRequest(
    repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    url: Uri.parse('https://huggingface.co/x/resolve/main/x.gguf'),
    expectedSizeBytes: expectedSizeBytes,
  );

  test(
    'enqueue succeeds: not pending, no error, backend recorded it',
    () async {
      final request = req();
      await container
          .read(downloadActionsControllerProvider.notifier)
          .enqueue(request);

      final state = container.read(downloadActionsControllerProvider);
      expect(state.isPending(request.taskId), isFalse);
      expect(state.errorFor(request.taskId), isNull);
      expect(backend.enqueuedRequests, contains(request.taskId));
    },
  );

  test(
    'enqueue failure (insufficient space) is surfaced per task id',
    () async {
      final huge = req(expectedSizeBytes: 999999999999);
      await container
          .read(downloadActionsControllerProvider.notifier)
          .enqueue(huge);

      final state = container.read(downloadActionsControllerProvider);
      expect(state.isPending(huge.taskId), isFalse);
      expect(
        state.errorFor(huge.taskId),
        isA<StorageInsufficientSpaceFailure>(),
      );
      expect(backend.enqueuedRequests, isNot(contains(huge.taskId)));
    },
  );

  test('a failed enqueue does not affect another task id', () async {
    final huge = req(expectedSizeBytes: 999999999999);
    final small = DownloadRequest(
      repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      url: Uri.parse('https://huggingface.co/x/resolve/main/y.gguf'),
      expectedSizeBytes: 1000,
    );
    await container
        .read(downloadActionsControllerProvider.notifier)
        .enqueue(huge);
    await container
        .read(downloadActionsControllerProvider.notifier)
        .enqueue(small);

    final state = container.read(downloadActionsControllerProvider);
    expect(state.errorFor(huge.taskId), isNotNull);
    expect(state.errorFor(small.taskId), isNull);
  });
}
