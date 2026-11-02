// Audit run-1 #7: Retry of a failed voice-model download must keep the pinned
// catalog URL and sha256, not rebuild a huggingface.co URL with no checksum.

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/features/models_hub/state/downloads_controller.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retry of a voice download keeps the pinned URL and sha256', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final dir = Directory.systemTemp.createTempSync('dl_retry_voice_');
    final backend = FakeDownloadBackend();
    final manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: dir,
    );
    final container = ProviderContainer(
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
    addTearDown(() async {
      container.dispose();
      await manager.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });

    final entry = voiceModelCatalog.firstWhere((e) => e.sha256 != null);
    final request = voiceModelDownloadRequest(entry);
    await container.read(downloadsControllerProvider.future);

    await manager.enqueue(request, freeBytes: 32000000000);
    backend.emit(
      BackendStatusUpdate(request.taskId, status: BackendTaskStatus.failed),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    backend.enqueuedRequests.clear();
    await container
        .read(downloadsControllerProvider.notifier)
        .retry(request.taskId);

    final retried = backend.enqueuedRequests[request.taskId];
    expect(retried, isNotNull);
    expect(retried!.url, entry.url);
    expect(retried.metaData, contains(entry.sha256!));
  });
}
