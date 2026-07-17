import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:drift/drift.dart' show Value;
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

  Future<int> insertRow({
    required String path,
    int sizeBytes = 100,
    DateTime? lastUsedAt,
  }) {
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
            lastUsedAt: Value(lastUsedAt),
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

  group('listInstalledModels ordering (Loop-4 read model)', () {
    test('most-recently-used first, nulls (never loaded) sort last', () async {
      await insertRow(
        path: '${tempDir.path}/never-used.gguf',
        lastUsedAt: null,
      );
      await insertRow(
        path: '${tempDir.path}/used-earlier.gguf',
        lastUsedAt: DateTime.utc(2026, 1, 1),
      );
      await insertRow(
        path: '${tempDir.path}/used-recently.gguf',
        lastUsedAt: DateTime.utc(2026, 7, 1),
      );

      final list = await manager(freeBytes: 1 << 30).listInstalledModels();
      expect(list.map((m) => m.fileName).toList(), [
        'used-recently.gguf',
        'used-earlier.gguf',
        'never-used.gguf', // null lastUsedAt — last, not first
      ]);
    });

    test('ties (including all-null) break by file name ascending', () async {
      await insertRow(path: '${tempDir.path}/charlie.gguf');
      await insertRow(path: '${tempDir.path}/alpha.gguf');
      await insertRow(path: '${tempDir.path}/bravo.gguf');

      final list = await manager(freeBytes: 1 << 30).listInstalledModels();
      expect(list.map((m) => m.fileName).toList(), [
        'alpha.gguf',
        'bravo.gguf',
        'charlie.gguf',
      ]);
    });
  });

  group('getInstalledModel', () {
    test('returns the row for a known id', () async {
      final id = await insertRow(path: '${tempDir.path}/a.gguf');
      final model = await manager(freeBytes: 1 << 30).getInstalledModel(id);
      expect(model, isNotNull);
      expect(model!.id, id);
    });

    test('returns null for an unknown id', () async {
      final model = await manager(freeBytes: 1 << 30).getInstalledModel(999);
      expect(model, isNull);
    });
  });

  group('touchLastUsed', () {
    test('stamps lastUsedAt to now', () async {
      final id = await insertRow(path: '${tempDir.path}/a.gguf');
      final before = DateTime.now();

      await manager(freeBytes: 1 << 30).touchLastUsed(id);

      final model = await manager(freeBytes: 1 << 30).getInstalledModel(id);
      expect(model!.lastUsedAt, isNotNull);
      expect(
        model.lastUsedAt!.isAfter(before.subtract(const Duration(seconds: 5))),
        isTrue,
      );
    });

    test('changes listInstalledModels ordering', () async {
      final oldId = await insertRow(
        path: '${tempDir.path}/old.gguf',
        lastUsedAt: DateTime.utc(2020, 1, 1),
      );
      await insertRow(
        path: '${tempDir.path}/newer.gguf',
        lastUsedAt: DateTime.utc(2026, 1, 1),
      );

      await manager(freeBytes: 1 << 30).touchLastUsed(oldId);

      final list = await manager(freeBytes: 1 << 30).listInstalledModels();
      expect(list.first.fileName, 'old.gguf');
    });

    test('throws StorageNotFoundFailure for an unknown id', () async {
      await expectLater(
        () => manager(freeBytes: 1 << 30).touchLastUsed(999),
        throwsA(isA<StorageNotFoundFailure>()),
      );
    });
  });

  group('vision models (Loop-7 T2 D5)', () {
    Future<int> insertVisionRow({
      required String path,
      required String mmprojPath,
      int sizeBytes = 100,
      int mmprojSizeBytes = 40,
    }) {
      File(path).writeAsBytesSync(List.filled(sizeBytes, 0));
      File(mmprojPath).writeAsBytesSync(List.filled(mmprojSizeBytes, 0));
      return db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'r/${path.hashCode}',
              fileName: path.split('/').last,
              sizeBytes: sizeBytes,
              localPath: path,
              downloadedAt: DateTime.utc(2026, 7, 18),
              isVision: const Value(true),
              mmprojPath: Value(mmprojPath),
            ),
          );
    }

    test('totalUsageBytes counts the mmproj projector file too, not just the '
        'model file', () async {
      await insertVisionRow(
        path: '${tempDir.path}/vision.gguf',
        mmprojPath: '${tempDir.path}/mmproj.gguf',
        sizeBytes: 100,
        mmprojSizeBytes: 40,
      );
      await insertRow(path: '${tempDir.path}/text-only.gguf', sizeBytes: 50);

      expect(await manager(freeBytes: 1 << 30).totalUsageBytes(), 190);
    });

    test('totalUsageBytes tolerates a projector path that no longer exists on '
        'disk (counts 0 for it rather than throwing)', () async {
      final id = await insertVisionRow(
        path: '${tempDir.path}/vision.gguf',
        mmprojPath: '${tempDir.path}/mmproj.gguf',
        sizeBytes: 100,
        mmprojSizeBytes: 40,
      );
      final row = await manager(freeBytes: 1 << 30).getInstalledModel(id);
      File(row!.mmprojPath!).deleteSync();

      expect(await manager(freeBytes: 1 << 30).totalUsageBytes(), 100);
    });

    test('delete removes the model file, the mmproj projector file, and the '
        'row — a vision model is one row but two files', () async {
      final modelPath = '${tempDir.path}/vision.gguf';
      final mmprojPath = '${tempDir.path}/mmproj.gguf';
      final id = await insertVisionRow(path: modelPath, mmprojPath: mmprojPath);

      await manager(freeBytes: 1 << 30).delete(id);

      expect(File(modelPath).existsSync(), isFalse);
      expect(File(mmprojPath).existsSync(), isFalse);
      expect(await db.select(db.installedModels).get(), isEmpty);
    });

    test('delete on a plain (non-vision) model does not touch mmprojPath at '
        'all (still null, no crash)', () async {
      final id = await insertRow(path: '${tempDir.path}/plain.gguf');
      await manager(freeBytes: 1 << 30).delete(id);
      expect(await db.select(db.installedModels).get(), isEmpty);
    });

    group('attachProjector', () {
      test('patches mmprojPath + isVision onto the matching (repoId, fileName) '
          'row', () async {
        File('${tempDir.path}/model.gguf').writeAsBytesSync([1, 2, 3]);
        final id = await db
            .into(db.installedModels)
            .insert(
              InstalledModelsCompanion.insert(
                repoId: 'ggml-org/SmolVLM-500M-Instruct-GGUF',
                fileName: 'SmolVLM-500M-Instruct-Q8_0.gguf',
                sizeBytes: 3,
                localPath: '${tempDir.path}/model.gguf',
                downloadedAt: DateTime.utc(2026, 7, 18),
                isVision: const Value(true),
              ),
            );

        await manager(freeBytes: 1 << 30).attachProjector(
          repoId: 'ggml-org/SmolVLM-500M-Instruct-GGUF',
          fileName: 'SmolVLM-500M-Instruct-Q8_0.gguf',
          mmprojPath: '${tempDir.path}/mmproj.gguf',
        );

        final row = await (db.select(
          db.installedModels,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(row.mmprojPath, '${tempDir.path}/mmproj.gguf');
        expect(row.isVision, isTrue);
      });

      test('throws StorageNotFoundFailure when no installed model matches '
          '(repoId, fileName)', () async {
        await expectLater(
          () => manager(freeBytes: 1 << 30).attachProjector(
            repoId: 'nobody/nothing',
            fileName: 'missing.gguf',
            mmprojPath: '${tempDir.path}/mmproj.gguf',
          ),
          throwsA(isA<StorageNotFoundFailure>()),
        );
      });
    });
  });
}
