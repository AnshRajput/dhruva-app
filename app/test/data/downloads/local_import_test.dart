import 'dart:io';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/local_import.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory sourceDir;
  late Directory modelsDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sourceDir = Directory.systemTemp.createTempSync('dhruva_import_src_');
    modelsDir = Directory.systemTemp.createTempSync('dhruva_import_dst_');
  });

  tearDown(() async {
    await db.close();
    for (final dir in [sourceDir, modelsDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  File ggufFile(String name, {List<int> extra = const [6, 7, 8]}) {
    final file = File('${sourceDir.path}/$name');
    file.writeAsBytesSync([
      0x47,
      0x47,
      0x55,
      0x46,
      ...extra,
    ]); // "GGUF" + payload
    return file;
  }

  test('imports a valid GGUF: copies, validates, registers in drift', () async {
    final source = ggufFile('MyModel-Q4_K_M.gguf');

    final info = await importLocalGguf(
      sourceFile: source,
      modelsDirectory: modelsDir,
      db: db,
      repoId: 'local/MyModel-Q4_K_M',
    );

    expect(File(info.localPath).existsSync(), isTrue);
    expect(info.sizeBytes, 7);
    expect(info.quant, 'Q4_K_M'); // auto-detected from filename
    expect(source.existsSync(), isTrue); // copy, not move — source untouched

    final rows = await db.select(db.installedModels).get();
    expect(rows, hasLength(1));
    expect(rows.single.repoId, 'local/MyModel-Q4_K_M');
  });

  test('an explicit quant overrides filename auto-detection', () async {
    final source = ggufFile('unlabeled-model.gguf');
    final info = await importLocalGguf(
      sourceFile: source,
      modelsDirectory: modelsDir,
      db: db,
      repoId: 'local/unlabeled-model',
      quant: 'Q5_K_M',
    );
    expect(info.quant, 'Q5_K_M');
  });

  test('rejects a file with the wrong magic bytes', () async {
    final source = File('${sourceDir.path}/not-really.gguf')
      ..writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);

    await expectLater(
      () => importLocalGguf(
        sourceFile: source,
        modelsDirectory: modelsDir,
        db: db,
        repoId: 'local/not-really',
      ),
      throwsA(isA<StorageCorruptFileFailure>()),
    );
    expect(await db.select(db.installedModels).get(), isEmpty);
  });

  test('rejects a too-short file', () async {
    final source = File('${sourceDir.path}/tiny.gguf')
      ..writeAsBytesSync([0x47, 0x47]);

    await expectLater(
      () => importLocalGguf(
        sourceFile: source,
        modelsDirectory: modelsDir,
        db: db,
        repoId: 'local/tiny',
      ),
      throwsA(isA<StorageCorruptFileFailure>()),
    );
  });

  test('throws StorageNotFoundFailure for a missing source file', () async {
    await expectLater(
      () => importLocalGguf(
        sourceFile: File('${sourceDir.path}/does-not-exist.gguf'),
        modelsDirectory: modelsDir,
        db: db,
        repoId: 'local/missing',
      ),
      throwsA(isA<StorageNotFoundFailure>()),
    );
  });

  test('creates the models directory if it does not exist yet', () async {
    final freshDir = Directory('${modelsDir.path}/nested/models');
    final source = ggufFile('m.gguf');

    final info = await importLocalGguf(
      sourceFile: source,
      modelsDirectory: freshDir,
      db: db,
      repoId: 'local/m',
    );

    expect(File(info.localPath).existsSync(), isTrue);
  });
}
