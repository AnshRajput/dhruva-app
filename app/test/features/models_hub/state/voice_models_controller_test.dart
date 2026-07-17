import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/features/models_hub/state/voice_models_controller.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late Directory modelsDir;
  late FakeDownloadBackend backend;
  late DownloadManager manager;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    modelsDir = Directory.systemTemp.createTempSync('voice_models_hub_test_');
    backend = FakeDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
    container = ProviderContainer(
      overrides: [
        downloadManagerProvider.overrideWith((ref) async => manager),
        modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await manager.dispose();
    await db.close();
    if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
  });

  test('every catalog entry starts notInstalled', () async {
    final state = await container.read(voiceModelsControllerProvider.future);
    expect(state, hasLength(voiceModelCatalog.length));
    expect(
      state.every((s) => s.status == VoiceModelStatus.notInstalled),
      isTrue,
    );
  });

  test(
    'downloading the VAD entry (single file, no extraction) installs it',
    () async {
      await container.read(voiceModelsControllerProvider.future);
      final notifier = container.read(voiceModelsControllerProvider.notifier);
      final entry = vadCatalogEntry;

      await notifier.download(entry);
      expect(_statusFor(container, entry.id), VoiceModelStatus.downloading);
      expect(
        backend.enqueuedRequests,
        contains('sherpa-voice/${entry.id}::${entry.archiveName}'),
      );

      // Simulate background_downloader's progress + completion, same as
      // `download_manager_test.dart` does — including writing the file the
      // manager's own completion handler expects to find on disk.
      final taskId = 'sherpa-voice/${entry.id}::${entry.archiveName}';
      backend.emit(
        BackendProgressUpdate(
          taskId,
          progress: 0.5,
          expectedFileSizeBytes: entry.downloadSizeBytes,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(_statusFor(container, entry.id), VoiceModelStatus.downloading);

      File(
        '${modelsDir.path}/${entry.archiveName}',
      ).writeAsBytesSync(List.filled(entry.downloadSizeBytes, 0));
      backend.emit(
        BackendStatusUpdate(taskId, status: BackendTaskStatus.complete),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(_statusFor(container, entry.id), VoiceModelStatus.installed);
    },
  );

  test('a failed download surfaces an error status', () async {
    await container.read(voiceModelsControllerProvider.future);
    final notifier = container.read(voiceModelsControllerProvider.notifier);
    final entry = vadCatalogEntry;
    final taskId = 'sherpa-voice/${entry.id}::${entry.archiveName}';

    await notifier.download(entry);
    backend.emit(
      BackendStatusUpdate(
        taskId,
        status: BackendTaskStatus.failed,
        errorMessage: 'network error',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final state = container.read(voiceModelsControllerProvider).value!;
    final row = state.firstWhere((s) => s.entry.id == entry.id);
    expect(row.status, VoiceModelStatus.failed);
    expect(row.errorMessage, isNotNull);
  });

  test('delete removes an installed VAD entry', () async {
    File('${modelsDir.path}/silero_vad.onnx').writeAsStringSync('x');
    await container.read(voiceModelsControllerProvider.future);
    expect(
      _statusFor(container, vadCatalogEntry.id),
      VoiceModelStatus.installed,
    );

    await container
        .read(voiceModelsControllerProvider.notifier)
        .delete(vadCatalogEntry);

    expect(
      _statusFor(container, vadCatalogEntry.id),
      VoiceModelStatus.notInstalled,
    );
    expect(File('${modelsDir.path}/silero_vad.onnx').existsSync(), isFalse);
  });
}

VoiceModelStatus _statusFor(ProviderContainer container, String entryId) {
  final state = container.read(voiceModelsControllerProvider).value!;
  return state.firstWhere((s) => s.entry.id == entryId).status;
}
