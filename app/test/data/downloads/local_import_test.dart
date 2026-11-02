import 'dart:io';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/local_import.dart';
import 'package:dhruva/data/downloads/model_file_channel.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_model_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory sourceDir;
  late Directory modelsDir;
  late FakeModelNative native;
  late ModelFileChannel channel;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sourceDir = Directory.systemTemp.createTempSync('dhruva_import_src_');
    modelsDir = Directory.systemTemp.createTempSync('dhruva_import_dst_');
    native = FakeModelNative();
    channel = native.install();
  });

  tearDown(() async {
    await db.close();
    for (final dir in [sourceDir, modelsDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  PickedModelFile ggufFile(String name, {List<int> extra = const [6, 7, 8]}) {
    final file = File('${sourceDir.path}/$name');
    file.writeAsBytesSync([
      0x47,
      0x47,
      0x55,
      0x46,
      ...extra,
    ]); // "GGUF" + payload
    return native.pickFile(file, name: name);
  }

  Future<InstalledModelInfo> import(
    PickedModelFile picked, {
    Directory? into,
    String? quant,
    int? freeBytes,
    void Function(int, int)? onProgress,
    ImportCancelToken? cancel,
  }) => importLocalGguf(
    picked: picked,
    channel: channel,
    modelsDirectory: into ?? modelsDir,
    db: db,
    repoId: 'local/${picked.name}',
    quant: quant,
    freeBytes: freeBytes,
    onProgress: onProgress,
    cancel: cancel,
  );

  test('imports a valid GGUF: copies, validates, registers in drift', () async {
    final info = await import(ggufFile('MyModel-Q4_K_M.gguf'));

    expect(File(info.localPath).existsSync(), isTrue);
    expect(info.sizeBytes, 7);
    expect(info.quant, 'Q4_K_M'); // auto-detected from filename
    expect(
      File('${modelsDir.path}/MyModel-Q4_K_M.gguf.part').existsSync(),
      isFalse,
    );

    final rows = await db.select(db.installedModels).get();
    expect(rows, hasLength(1));
    expect(rows.single.repoId, 'local/MyModel-Q4_K_M.gguf');
  });

  test('an explicit quant overrides filename auto-detection', () async {
    final info = await import(
      ggufFile('unlabeled-model.gguf'),
      quant: 'Q5_K_M',
    );
    expect(info.quant, 'Q5_K_M');
  });

  test(
    'rejects a file with the wrong magic bytes and leaves nothing',
    () async {
      final file = File('${sourceDir.path}/not-really.gguf')
        ..writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);

      await expectLater(
        import(native.pickFile(file)),
        throwsA(isA<StorageCorruptFileFailure>()),
      );
      expect(await db.select(db.installedModels).get(), isEmpty);
      expect(modelsDir.listSync(), isEmpty);
    },
  );

  test('rejects a too-short file', () async {
    final file = File('${sourceDir.path}/tiny.gguf')
      ..writeAsBytesSync([0x47, 0x47]);
    await expectLater(
      import(native.pickFile(file)),
      throwsA(isA<StorageCorruptFileFailure>()),
    );
  });

  test('a name that is not .gguf is rejected before any native copy', () async {
    final file = File('${sourceDir.path}/notes.txt')..writeAsBytesSync([1, 2]);
    await expectLater(
      import(native.pickFile(file)),
      throwsA(isA<StorageCorruptFileFailure>()),
    );
    expect(native.calls, isNot(contains('copy')));
  });

  test('an unreadable source maps to a typed IO failure', () async {
    const gone = PickedModelFile(
      uri: 'content://fake/gone',
      name: 'gone.gguf',
      size: 10,
    );
    await expectLater(import(gone), throwsA(isA<StorageIoFailure>()));
    expect(modelsDir.listSync(), isEmpty);
  });

  test(
    'importing the same file twice upserts in place — no crash, no duplicate',
    () async {
      final picked = ggufFile('Repeated-Q4_K_M.gguf');
      final first = await import(picked);
      final second = await import(picked);

      expect(second.sizeBytes, first.sizeBytes);
      expect(await db.select(db.installedModels).get(), hasLength(1));
      expect(File(second.localPath).existsSync(), isTrue);
    },
  );

  test('creates the models directory if it does not exist yet', () async {
    final freshDir = Directory('${modelsDir.path}/nested/models');
    final info = await import(ggufFile('m.gguf'), into: freshDir);
    expect(File(info.localPath).existsSync(), isTrue);
  });

  test('localImportExists detects a duplicate by file name', () async {
    expect(localImportExists(modelsDir, 'dup.gguf'), isFalse);
    await import(ggufFile('dup.gguf'));
    expect(localImportExists(modelsDir, 'dup.gguf'), isTrue);
  });

  test('insufficient free space throws up front and copies nothing', () async {
    await expectLater(
      import(ggufFile('big.gguf'), freeBytes: 3),
      throwsA(isA<StorageInsufficientSpaceFailure>()),
    );
    expect(modelsDir.listSync(), isEmpty);
    expect(native.calls, isNot(contains('copy')));
  });

  test(
    'a disk that fills mid-copy gives the space failure, no partial',
    () async {
      native
        ..copyError = 'no_space'
        ..failAfterBytes = 5;
      await expectLater(
        import(ggufFile('fills.gguf', extra: List.filled(100, 1))),
        throwsA(isA<StorageInsufficientSpaceFailure>()),
      );
      expect(modelsDir.listSync(), isEmpty);
      expect(await db.select(db.installedModels).get(), isEmpty);
    },
  );

  test(
    'cancel mid-copy tells native, removes the partial, registers nothing',
    () async {
      final token = ImportCancelToken();
      await expectLater(
        import(
          ggufFile('cancel.gguf', extra: List.filled(2000, 1)),
          cancel: token,
          onProgress: (_, _) => token.cancel(),
        ),
        throwsA(isA<ImportCancelled>()),
      );
      expect(native.calls, contains('cancel'));
      expect(modelsDir.listSync(), isEmpty);
      expect(await db.select(db.installedModels).get(), isEmpty);
    },
  );

  test('a failed copy keeps an existing model of the same name', () async {
    final existing = File('${modelsDir.path}/f.gguf')..writeAsStringSync('old');
    native.copyError = 'failed';
    await expectLater(
      import(ggufFile('f.gguf')),
      throwsA(isA<StorageIoFailure>()),
    );
    expect(existing.readAsStringSync(), 'old');
    expect(await db.select(db.installedModels).get(), isEmpty);
  });

  test('reports progress up to the full size', () async {
    var last = 0;
    await import(
      ggufFile('p.gguf'),
      onProgress: (copied, total) => last = copied,
    );
    expect(last, 7);
  });

  group('ModelFileChannel.pick', () {
    test('returns the picked file, name stripped to its basename', () async {
      native.pickResult = {
        'uri': 'content://x/1',
        'name': '../../evil/Model.gguf',
        'size': 42,
      };
      final picked = await channel.pick();
      expect(picked!.name, 'Model.gguf');
      expect(picked.size, 42);
    });

    test('null when the user cancels the picker', () async {
      native.pickResult = null;
      expect(await channel.pick(), isNull);
    });

    test('a native failure becomes a ModelFileException', () async {
      native.pickError = 'no_picker';
      await expectLater(
        channel.pick(),
        throwsA(
          isA<ModelFileException>().having((e) => e.code, 'code', 'no_picker'),
        ),
      );
    });
  });
}
