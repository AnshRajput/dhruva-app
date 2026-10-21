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

  test(
    'importing the same file twice upserts in place — no crash, no duplicate row '
    '(attack #8: defined upsert behavior)',
    () async {
      final source = ggufFile('Repeated-Q4_K_M.gguf');

      final first = await importLocalGguf(
        sourceFile: source,
        modelsDirectory: modelsDir,
        db: db,
        repoId: 'local/Repeated-Q4_K_M',
      );
      final second = await importLocalGguf(
        sourceFile: source,
        modelsDirectory: modelsDir,
        db: db,
        repoId: 'local/Repeated-Q4_K_M',
      );

      expect(second.sizeBytes, first.sizeBytes);
      final rows = await db.select(db.installedModels).get();
      expect(rows, hasLength(1)); // not duplicated
      expect(File(second.localPath).existsSync(), isTrue);
    },
  );

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

  test('rejects a non-GGUF file without writing anything', () async {
    final bad = File('${sourceDir.path}/bad.gguf')
      ..writeAsBytesSync([1, 2, 3, 4, 5]);
    await expectLater(
      importLocalGguf(
        sourceFile: bad,
        modelsDirectory: modelsDir,
        db: db,
        repoId: 'local/bad',
      ),
      throwsA(isA<StorageCorruptFileFailure>()),
    );
    expect(modelsDir.listSync(), isEmpty);
  });

  test('localImportExists detects a duplicate by file name', () async {
    expect(localImportExists(modelsDir, 'dup.gguf'), isFalse);
    await importLocalGguf(
      sourceFile: ggufFile('dup.gguf'),
      modelsDirectory: modelsDir,
      db: db,
      repoId: 'local/dup',
    );
    expect(localImportExists(modelsDir, 'dup.gguf'), isTrue);
  });

  test('insufficient free space throws and writes nothing', () async {
    await expectLater(
      importLocalGguf(
        sourceFile: ggufFile('big.gguf'),
        modelsDirectory: modelsDir,
        db: db,
        repoId: 'local/big',
        freeBytes: 3,
      ),
      throwsA(isA<StorageInsufficientSpaceFailure>()),
    );
    expect(modelsDir.listSync(), isEmpty);
  });

  test(
    'cancel mid-copy removes the partial file and registers nothing',
    () async {
      final token = ImportCancelToken();
      final source = ggufFile('cancel.gguf', extra: List.filled(200000, 1));
      await expectLater(
        importLocalGguf(
          sourceFile: source,
          modelsDirectory: modelsDir,
          db: db,
          repoId: 'local/cancel',
          cancel: token,
          onProgress: (_, _) => token.cancel(),
        ),
        throwsA(isA<ImportCancelled>()),
      );
      expect(modelsDir.listSync(), isEmpty);
      expect(await db.select(db.installedModels).get(), isEmpty);
    },
  );

  test(
    'copy failure cleans the partial file and keeps an existing model',
    () async {
      // Existing model at the destination; a directory squatting on the .part
      // path makes openWrite fail -> StorageIoFailure, existing file intact.
      final existing = File('${modelsDir.path}/f.gguf')
        ..writeAsStringSync('old');
      Directory('${modelsDir.path}/f.gguf.part').createSync();
      await expectLater(
        importLocalGguf(
          sourceFile: ggufFile('f.gguf'),
          modelsDirectory: modelsDir,
          db: db,
          repoId: 'local/f',
        ),
        throwsA(isA<StorageIoFailure>()),
      );
      expect(existing.readAsStringSync(), 'old');
      expect(await db.select(db.installedModels).get(), isEmpty);
    },
  );

  test('reports progress up to the full size', () async {
    var last = 0;
    await importLocalGguf(
      sourceFile: ggufFile('p.gguf'),
      modelsDirectory: modelsDir,
      db: db,
      repoId: 'local/p',
      onProgress: (copied, total) => last = copied,
    );
    expect(last, 7);
  });
}
