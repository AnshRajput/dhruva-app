import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/models_hub/state/storage_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

/// `modelsDirectoryProvider` resolves via `path_provider`, which needs a
/// platform channel — fake the plugin so `importLocal` can run under `test`.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String path;
  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('dhruva_storage_ctrl_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
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
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('build() reflects installed rows and totals their size', () async {
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r/a',
            fileName: 'a.gguf',
            sizeBytes: 100,
            localPath: '${tempDir.path}/a.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r/b',
            fileName: 'b.gguf',
            sizeBytes: 250,
            localPath: '${tempDir.path}/b.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );

    final state = await container.read(storageControllerProvider.future);
    expect(state.installed, hasLength(2));
    expect(state.totalBytes, 350);
    expect(state.actionError, isNull);
  });

  test('G2 picker-pollution guard: a sherpa-voice/ row never appears in the '
      'GGUF storage list or its totalBytes (this tab is GGUF-only by '
      'design — the Voice tab and Settings\' separate storage summary are '
      'where voice-model bytes are accounted for)', () async {
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r/a',
            fileName: 'a.gguf',
            sizeBytes: 100,
            localPath: '${tempDir.path}/a.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'sherpa-voice/whisper-tiny',
            fileName: 'sherpa-onnx-whisper-tiny.tar.bz2',
            sizeBytes: 111000000,
            localPath: '${tempDir.path}/whisper.tar.bz2',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );

    final state = await container.read(storageControllerProvider.future);

    expect(state.installed, hasLength(1));
    expect(state.installed.single.repoId, 'r/a');
    expect(
      state.installed.any((m) => m.repoId.startsWith('sherpa-voice/')),
      isFalse,
    );
    expect(
      state.totalBytes,
      100,
      reason: 'total is derived from the already-filtered list',
    );
  });

  test('delete() removes the row and clears from the list', () async {
    final file = File('${tempDir.path}/a.gguf')..writeAsBytesSync([1, 2, 3]);
    final id = await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r/a',
            fileName: 'a.gguf',
            sizeBytes: 3,
            localPath: file.path,
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await container.read(storageControllerProvider.future);

    await container.read(storageControllerProvider.notifier).delete(id);

    final state = container.read(storageControllerProvider).value!;
    expect(state.installed, isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('delete() on an unknown id sets actionError, keeps the list', () async {
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r/a',
            fileName: 'a.gguf',
            sizeBytes: 3,
            localPath: '${tempDir.path}/a.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await container.read(storageControllerProvider.future);

    await container.read(storageControllerProvider.notifier).delete(999);

    final state = container.read(storageControllerProvider).value!;
    expect(state.installed, hasLength(1)); // untouched
    expect(state.actionError, isNotNull);
  });

  test('importLocal() validates, copies, and registers a GGUF', () async {
    await container.read(storageControllerProvider.future);
    final source = File('${tempDir.path}/source.gguf')
      ..writeAsBytesSync([0x47, 0x47, 0x55, 0x46, 1, 2, 3]);

    await container
        .read(storageControllerProvider.notifier)
        .importLocal(source);

    final state = container.read(storageControllerProvider).value!;
    expect(state.installed, hasLength(1));
    expect(state.installed.single.repoId, 'local/source');
    expect(state.actionError, isNull);
  });

  test('importLocal() surfaces a typed failure for a non-GGUF file', () async {
    await container.read(storageControllerProvider.future);
    final source = File('${tempDir.path}/not-gguf.gguf')
      ..writeAsBytesSync([0, 0, 0, 0]);

    await container
        .read(storageControllerProvider.notifier)
        .importLocal(source);

    final state = container.read(storageControllerProvider).value!;
    expect(state.installed, isEmpty);
    expect(state.actionError, isNotNull);
  });
}
