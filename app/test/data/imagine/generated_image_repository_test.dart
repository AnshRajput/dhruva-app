import 'dart:io';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/imagine/generated_image_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late GeneratedImageRepository repo;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = GeneratedImageRepository(db: db);
    tempDir = await Directory.systemTemp.createTemp('imagine_repo_test');
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('insert then list returns newest first', () async {
    await repo.insert(
      prompt: 'first',
      negativePrompt: '',
      filePath: '${tempDir.path}/a.png',
      width: 512,
      height: 512,
      steps: 20,
      seed: -1,
      cfgScale: 7,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repo.insert(
      prompt: 'second',
      negativePrompt: 'blurry',
      filePath: '${tempDir.path}/b.png',
      width: 384,
      height: 384,
      steps: 15,
      seed: 42,
      cfgScale: 9,
    );

    final rows = await repo.list();
    expect(rows, hasLength(2));
    expect(rows.first.prompt, 'second');
    expect(rows.first.seed, 42);
    expect(rows.last.prompt, 'first');
  });

  test('delete removes the row and the file on disk', () async {
    final file = File('${tempDir.path}/img.png')..writeAsBytesSync([1, 2, 3]);
    final id = await repo.insert(
      prompt: 'p',
      negativePrompt: '',
      filePath: file.path,
      width: 512,
      height: 512,
      steps: 20,
      seed: -1,
      cfgScale: 7,
    );

    await repo.delete(id);

    expect(await repo.list(), isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('delete throws StorageNotFoundFailure for an unknown id', () async {
    expect(() => repo.delete(999), throwsA(isA<StorageNotFoundFailure>()));
  });
}
