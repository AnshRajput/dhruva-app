/// Loop 6 QA: pins the deliberate design split flagged in the
/// [flutter-core → qa-tester, reviewer] HANDOFF — `storage_controller.dart`
/// (Models hub "Installed" tab) filters out `sherpa-voice/` rows so voice
/// models don't pollute the GGUF list, but `storageSummaryProvider`
/// (Settings' storage section) deliberately does NOT filter, because it's
/// meant to report real disk usage. No existing test covered either
/// direction of this contract; this file locks in the "don't filter here"
/// half (`storage_controller_test.dart` locks in the "do filter there"
/// half).
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
    'unlike the Models hub Installed tab, Settings\' storage summary DOES '
    'count sherpa-voice/ (voice model) bytes — real disk usage, by design',
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

      expect(summary.modelCount, 2);
      expect(summary.totalBytes, 300);
    },
  );
}
