/// Pins ONE counting rule across the app: `storage_controller.dart` (Models hub
/// "Installed" tab) and `storageSummaryProvider` (Settings' storage line) both
/// count language models only. Voice files (`sherpa-voice/`) are reported
/// separately, so Settings never says "4 models" over an Installed tab that
/// says "1 installed" (wave 4 re-audit, issue 7).
library;

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/settings/state/storage_summary_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'one counting rule: the storage summary counts language models only, and '
    'reports sherpa-voice/ bytes apart (they are not "models")',
    () async {
      await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'r/a',
              fileName: 'a.gguf',
              sizeBytes: 100,
              localPath: '/tmp/a.gguf',
              downloadedAt: DateTime.utc(2026, 7, 17),
            ),
          );
      await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'sherpa-voice/whisper-tiny',
              fileName: 'sherpa-onnx-whisper-tiny.tar.bz2',
              sizeBytes: 200,
              localPath: '/tmp/whisper.tar.bz2',
              downloadedAt: DateTime.utc(2026, 7, 17),
            ),
          );

      final summary = await container.read(storageSummaryProvider.future);

      expect(summary.modelCount, 1);
      expect(summary.totalBytes, 100);
      expect(summary.voiceBytes, 200);
    },
  );
}
