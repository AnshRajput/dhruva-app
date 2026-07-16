import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('dhruva_storage_test_');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  StorageManager manager({
    required int freeBytes,
    int totalBytes = 64000000000,
  }) => StorageManager(
    db: db,
    deviceInfo: FakeDeviceInfoService(
      memory: const DeviceMemoryInfo(
        totalBytes: 4000000000,
        availableBytes: 1000000000,
      ),
      storage: DeviceStorageInfo(totalBytes: totalBytes, freeBytes: freeBytes),
    ),
  );

  Future<int> insertRow({required String path, int sizeBytes = 100}) {
    File(path).writeAsBytesSync(List.filled(sizeBytes, 0));
    return db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r/${path.hashCode}',
            fileName: path.split('/').last,
            sizeBytes: sizeBytes,
            localPath: path,
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
  }

  test('listInstalledModels reflects drift rows', () async {
    await insertRow(path: '${tempDir.path}/a.gguf');
    await insertRow(path: '${tempDir.path}/b.gguf');

    final list = await manager(freeBytes: 1 << 30).listInstalledModels();
    expect(list, hasLength(2));
  });

  test('totalUsageBytes sums installed model sizes', () async {
    await insertRow(path: '${tempDir.path}/a.gguf', sizeBytes: 100);
    await insertRow(path: '${tempDir.path}/b.gguf', sizeBytes: 250);

    expect(await manager(freeBytes: 1 << 30).totalUsageBytes(), 350);
  });

  test('totalUsageBytes is zero with nothing installed', () async {
    expect(await manager(freeBytes: 1 << 30).totalUsageBytes(), 0);
  });

  test('delete removes both the file and the drift row', () async {
    final path = '${tempDir.path}/a.gguf';
    final id = await insertRow(path: path);

    await manager(freeBytes: 1 << 30).delete(id);

    expect(File(path).existsSync(), isFalse);
    expect(await db.select(db.installedModels).get(), isEmpty);
  });

  test('delete on an unknown id throws StorageNotFoundFailure', () async {
    await expectLater(
      () => manager(freeBytes: 1 << 30).delete(999),
      throwsA(isA<StorageNotFoundFailure>()),
    );
  });

  test(
    'delete still removes the drift row when the file is already gone',
    () async {
      final path = '${tempDir.path}/a.gguf';
      final id = await insertRow(path: path);
      File(path).deleteSync();

      await manager(freeBytes: 1 << 30).delete(id);
      expect(await db.select(db.installedModels).get(), isEmpty);
    },
  );

  group('guardFreeSpace', () {
    test('passes when there is enough free space', () async {
      await manager(
        freeBytes: 2 * 1024 * 1024 * 1024,
      ).guardFreeSpace(1024 * 1024 * 1024);
    });

    test('throws StorageInsufficientSpaceFailure when there is not', () async {
      await expectLater(
        () => manager(freeBytes: 1000).guardFreeSpace(1024 * 1024 * 1024),
        throwsA(isA<StorageInsufficientSpaceFailure>()),
      );
    });
  });
}
