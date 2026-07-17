import 'dart:io';

import 'package:dhruva/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Behaves exactly like the real shipped v3 schema (pre-Loop-7): every
/// table `character_migration_test.dart`'s v2->v3 test already covers, but
/// `installed_models` WITHOUT `mmproj_path`/`is_vision` — same
/// createTable-then-DROP-COLUMN trick that file documents (no
/// schema-snapshot codegen to diff against in this repo).
class _V3Database extends AppDatabase {
  _V3Database(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createTable(installedModels);
      await m.createTable(folders);
      await m.createTable(conversations);
      await m.createTable(messages);
      await m.createTable(characters);
      await customStatement(
        'ALTER TABLE installed_models DROP COLUMN mmproj_path',
      );
      await customStatement(
        'ALTER TABLE installed_models DROP COLUMN is_vision',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_messages_conversation '
        'ON messages (conversation_id)',
      );
    },
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dhruva_vision_migration');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('v3 -> v4 migration preserves existing installed models and adds '
      'mmproj_path/is_vision, defaulting is_vision to false', () async {
    final dbFile = File(p.join(tempDir.path, 'v3.sqlite'));

    final v3 = _V3Database(NativeDatabase(dbFile));
    expect(v3.schemaVersion, 3);
    final now = DateTime.utc(2026, 7, 18);
    final modelId = await v3
        .into(v3.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
            fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
            sizeBytes: 770000000,
            localPath: '/data/models/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
            downloadedAt: now,
          ),
        );
    await v3.close();

    // Reopen with the real (v4) AppDatabase over the same file — this
    // must trigger the real onUpgrade(3, 4).
    final v4 = AppDatabase(NativeDatabase(dbFile));
    expect(v4.schemaVersion, 4);

    final rows = await v4.select(v4.installedModels).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, modelId);
    expect(rows.single.repoId, 'bartowski/Llama-3.2-1B-Instruct-GGUF');
    // New columns, unset on the pre-existing row.
    expect(rows.single.mmprojPath, null);
    expect(rows.single.isVision, isFalse);

    // The new columns are usable post-migration — a vision model row can
    // now record where its projector landed.
    final visionId = await v4
        .into(v4.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'ggml-org/SmolVLM-500M-Instruct-GGUF',
            fileName: 'SmolVLM-500M-Instruct-Q8_0.gguf',
            sizeBytes: 436207616,
            localPath: '/data/models/SmolVLM-500M-Instruct-Q8_0.gguf',
            downloadedAt: now,
            isVision: const Value(true),
          ),
        );
    await (v4.update(
      v4.installedModels,
    )..where((t) => t.id.equals(visionId))).write(
      const InstalledModelsCompanion(
        mmprojPath: Value('/data/models/mmproj-SmolVLM-500M-Q8_0.gguf'),
      ),
    );
    final vision = await (v4.select(
      v4.installedModels,
    )..where((t) => t.id.equals(visionId))).getSingle();
    expect(vision.isVision, isTrue);
    expect(vision.mmprojPath, '/data/models/mmproj-SmolVLM-500M-Q8_0.gguf');

    await v4.close();
  });

  test('a fresh v4 database has the mmproj_path/is_vision columns', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final id = await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'r/m',
            fileName: 'm.gguf',
            sizeBytes: 1,
            localPath: '/models/m.gguf',
            downloadedAt: DateTime.utc(2026, 7, 18),
            isVision: const Value(true),
          ),
        );
    final row = await (db.select(
      db.installedModels,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.isVision, isTrue);
    expect(row.mmprojPath, null);
    await db.close();
  });
}
