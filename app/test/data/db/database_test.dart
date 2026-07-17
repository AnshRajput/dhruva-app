import 'package:dhruva/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('insert + select round-trips a row', () async {
    final id = await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
            fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
            quant: const Value('Q4_K_M'),
            sizeBytes: 770000000,
            localPath: '/data/models/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
            license: const Value('llama3.2'),
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );

    final row = await (db.select(
      db.installedModels,
    )..where((t) => t.id.equals(id))).getSingle();

    expect(row.repoId, 'bartowski/Llama-3.2-1B-Instruct-GGUF');
    expect(row.quant, 'Q4_K_M');
    expect(row.sizeBytes, 770000000);
    expect(row.gated, isFalse); // withDefault(false)
    expect(row.lastUsedAt, null);
  });

  test(
    'repoId + fileName is unique — upsertInstalledModel updates in place, not a duplicate row',
    () async {
      final companion = InstalledModelsCompanion.insert(
        repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
        fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
        sizeBytes: 986048768,
        localPath: '/data/models/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
        downloadedAt: DateTime.utc(2026, 7, 17),
      );
      await db.upsertInstalledModel(companion);
      await db.upsertInstalledModel(
        companion.copyWith(sizeBytes: const Value(986048769)),
      );

      final rows = await db.select(db.installedModels).get();
      expect(rows, hasLength(1));
      expect(rows.single.sizeBytes, 986048769);
    },
  );

  test(
    'a bare insertOnConflictUpdate does NOT dedupe on repoId+fileName '
    '(only on the primary key) — upsertInstalledModel exists to fix this',
    () async {
      final companion = InstalledModelsCompanion.insert(
        repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
        fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
        sizeBytes: 1,
        localPath: '/data/models/x.gguf',
        downloadedAt: DateTime.utc(2026, 7, 17),
      );
      await db.into(db.installedModels).insertOnConflictUpdate(companion);
      await expectLater(
        () => db.into(db.installedModels).insertOnConflictUpdate(companion),
        throwsA(anything),
      );
    },
  );

  test(
    'a genuinely duplicate insert() (not insertOnConflictUpdate) throws',
    () async {
      final companion = InstalledModelsCompanion.insert(
        repoId: 'dup/repo',
        fileName: 'dup.gguf',
        sizeBytes: 1,
        localPath: '/data/models/dup.gguf',
        downloadedAt: DateTime.utc(2026, 7, 17),
      );
      await db.into(db.installedModels).insert(companion);
      await expectLater(
        () => db.into(db.installedModels).insert(companion),
        throwsA(anything),
      );
    },
  );

  test('delete removes the row', () async {
    final id = await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r',
            fileName: 'f.gguf',
            sizeBytes: 1,
            localPath: '/data/models/f.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await (db.delete(db.installedModels)..where((t) => t.id.equals(id))).go();
    final rows = await db.select(db.installedModels).get();
    expect(rows, isEmpty);
  });

  test('multiple quants of the same repo are separate rows', () async {
    for (final quant in ['Q4_K_M', 'Q8_0']) {
      await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
              fileName: 'Qwen2.5-1.5B-Instruct-$quant.gguf',
              quant: Value(quant),
              sizeBytes: 1,
              localPath: '/data/models/Qwen2.5-1.5B-Instruct-$quant.gguf',
              downloadedAt: DateTime.utc(2026, 7, 17),
            ),
          );
    }
    final rows = await db.select(db.installedModels).get();
    expect(rows, hasLength(2));
  });

  test('schemaVersion is 3', () {
    expect(db.schemaVersion, 3);
  });

  group('generated row/companion surface', () {
    final downloadedAt = DateTime.utc(2026, 7, 17);
    InstalledModel row({DateTime? lastUsedAt}) => InstalledModel(
      id: 1,
      repoId: 'r/m',
      fileName: 'm-Q4_K_M.gguf',
      quant: 'Q4_K_M',
      sizeBytes: 100,
      sha256: 'a' * 64,
      localPath: '/data/models/m-Q4_K_M.gguf',
      license: 'apache-2.0',
      gated: false,
      downloadedAt: downloadedAt,
      lastUsedAt: lastUsedAt,
    );

    test('toJson / fromJson round-trip', () {
      final json = row().toJson();
      final restored = InstalledModel.fromJson(json);
      // Compare fields individually rather than full object equality: the
      // default JSON serializer round-trips DateTime through a local-time
      // string, so `restored.downloadedAt` may not be `isUtc` even though
      // it names the same instant — `isAtSameMomentAs` is the correct check.
      expect(restored.id, row().id);
      expect(restored.repoId, row().repoId);
      expect(restored.fileName, row().fileName);
      expect(restored.quant, row().quant);
      expect(restored.sizeBytes, row().sizeBytes);
      expect(restored.sha256, row().sha256);
      expect(restored.localPath, row().localPath);
      expect(restored.license, row().license);
      expect(restored.gated, row().gated);
      expect(
        restored.downloadedAt.isAtSameMomentAs(row().downloadedAt),
        isTrue,
      );
      expect(restored.lastUsedAt, row().lastUsedAt);
    });

    test('value equality + hashCode + toString', () {
      final a = row();
      final b = row();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('InstalledModel'));
      expect(a, isNot(row(lastUsedAt: downloadedAt)));
    });

    test('copyWith overrides only the given fields', () {
      final updated = row().copyWith(
        sizeBytes: 200,
        quant: const Value('Q8_0'),
      );
      expect(updated.sizeBytes, 200);
      expect(updated.quant, 'Q8_0');
      expect(updated.repoId, row().repoId);
    });

    test('copyWithCompanion applies present-only companion fields', () {
      final companion = InstalledModelsCompanion(sizeBytes: const Value(999));
      final updated = row().copyWithCompanion(companion);
      expect(updated.sizeBytes, 999);
      expect(updated.repoId, row().repoId); // untouched field kept
    });

    test('toCompanion round-trips into an insertable companion', () async {
      final companion = row().toCompanion(true);
      await db
          .into(db.installedModels)
          .insert(companion, mode: InsertMode.insertOrReplace);
      final fetched = await (db.select(
        db.installedModels,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(fetched.repoId, 'r/m');
    });

    test(
      'InstalledModelsCompanion.custom builds an insertable from raw expressions',
      () async {
        final insertable = InstalledModelsCompanion.custom(
          repoId: const Constant('r/custom'),
          fileName: const Constant('custom.gguf'),
          sizeBytes: const Constant(1),
          localPath: const Constant('/models/custom.gguf'),
          downloadedAt: Constant(downloadedAt),
        );
        await db.into(db.installedModels).insert(insertable);
        final fetched = await (db.select(
          db.installedModels,
        )..where((t) => t.repoId.equals('r/custom'))).getSingle();
        expect(fetched.fileName, 'custom.gguf');
      },
    );

    test('companion equality + toString', () {
      const a = InstalledModelsCompanion(sizeBytes: Value(1));
      const b = InstalledModelsCompanion(sizeBytes: Value(1));
      expect(a, b);
      expect(a.toString(), contains('InstalledModelsCompanion'));
    });
  });

  group('query builder surface (filters + orderings across every column)', () {
    setUp(() async {
      await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'a/repo',
              fileName: 'a.gguf',
              quant: const Value('Q4_K_M'),
              sizeBytes: 100,
              sha256: const Value('deadbeef'),
              localPath: '/models/a.gguf',
              license: const Value('mit'),
              gated: const Value(true),
              downloadedAt: DateTime.utc(2026, 1, 1),
              lastUsedAt: Value(DateTime.utc(2026, 2, 1)),
            ),
          );
      await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'b/repo',
              fileName: 'b.gguf',
              sizeBytes: 200,
              localPath: '/models/b.gguf',
              downloadedAt: DateTime.utc(2026, 3, 1),
            ),
          );
    });

    test(
      'filtering + ordering across every column resolves the expected row',
      () async {
        final query = db.select(db.installedModels)
          ..where(
            (t) =>
                t.repoId.equals('a/repo') &
                t.fileName.equals('a.gguf') &
                t.quant.equals('Q4_K_M') &
                t.sizeBytes.equals(100) &
                t.sha256.equals('deadbeef') &
                t.localPath.equals('/models/a.gguf') &
                t.license.equals('mit') &
                t.gated.equals(true) &
                t.downloadedAt.equals(DateTime.utc(2026, 1, 1)) &
                t.lastUsedAt.equals(DateTime.utc(2026, 2, 1)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sizeBytes)]);

        final rows = await query.get();
        expect(rows, hasLength(1));
        expect(rows.single.repoId, 'a/repo');
      },
    );

    test('sizeBytes descending ordering puts the larger file first', () async {
      final rows = await (db.select(
        db.installedModels,
      )..orderBy([(t) => OrderingTerm.desc(t.sizeBytes)])).get();
      expect(rows.first.repoId, 'b/repo');
    });

    test('watch emits on insert', () async {
      final stream = db.select(db.installedModels).watch();
      final firstTwo = await stream.take(1).first;
      expect(firstTwo, hasLength(2));
    });
  });
}
