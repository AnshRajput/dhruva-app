import 'dart:io';

import 'package:dhruva/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Behaves exactly like the real v1 schema (the shipped Loop-3 db): only
/// `installed_models`, `schemaVersion` 1. Subclassing the real
/// `AppDatabase` — rather than hand-typing `CREATE TABLE` DDL — means the
/// "existing data" this test seeds is created through the exact same
/// generated `InstalledModels` table code real users' v1 databases were
/// built from.
class _V1Database extends AppDatabase {
  _V1Database(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createTable(installedModels);
      // No schema-snapshot codegen in this repo (see build.yaml's doc
      // comment) — `createTable` always builds the table's CURRENT (v4)
      // shape, including the Loop-7 mmproj_path/is_vision columns that
      // didn't exist at v1. Drop them so the later real onUpgrade(1, 4)'s
      // `addColumn` calls have something to add, same trick
      // character_migration_test.dart's `_V2Database` already uses for
      // `conversations.character_id`.
      await customStatement(
        'ALTER TABLE installed_models DROP COLUMN mmproj_path',
      );
      await customStatement(
        'ALTER TABLE installed_models DROP COLUMN is_vision',
      );
    },
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dhruva_chat_migration');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'v1 -> v2 migration preserves existing installed_models data and adds the chat tables',
    () async {
      final dbFile = File(p.join(tempDir.path, 'v1.sqlite'));

      // Seed a real v1 database and insert a row.
      final v1 = _V1Database(NativeDatabase(dbFile));
      await v1
          .into(v1.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
              fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
              quant: const Value('Q4_K_M'),
              sizeBytes: 770000000,
              localPath: '/data/models/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
              downloadedAt: DateTime.utc(2026, 7, 1),
            ),
          );
      expect(v1.schemaVersion, 1);
      await v1.close();

      // Reopen with the real (current, v4) AppDatabase over the same file —
      // this must trigger the real onUpgrade(1, 4), running the v1->v2,
      // v2->v3, and v3->v4 branches in one jump (see database.dart's
      // migration doc).
      final v2 = AppDatabase(NativeDatabase(dbFile));
      expect(v2.schemaVersion, 4);

      final installedRows = await v2.select(v2.installedModels).get();
      expect(installedRows, hasLength(1));
      expect(
        installedRows.single.repoId,
        'bartowski/Llama-3.2-1B-Instruct-GGUF',
      );
      expect(installedRows.single.sizeBytes, 770000000);

      // New tables exist and are usable post-migration.
      final folderId = await v2
          .into(v2.folders)
          .insert(FoldersCompanion.insert(name: 'Work'));
      final now = DateTime.utc(2026, 7, 17);
      final conversationId = await v2
          .into(v2.conversations)
          .insert(
            ConversationsCompanion.insert(
              folderId: Value(folderId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await v2
          .into(v2.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: conversationId,
              role: MessageRole.user,
              status: MessageStatus.complete,
              createdAt: now,
            ),
          );

      final messages = await v2.select(v2.messages).get();
      expect(messages, hasLength(1));
      expect(messages.single.conversationId, conversationId);

      await v2.close();
    },
  );

  test('a fresh database creates all five tables directly', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 4);
    expect(
      db.allTables.map((t) => t.actualTableName),
      containsAll(<String>[
        'installed_models',
        'folders',
        'conversations',
        'messages',
        'characters',
      ]),
    );
    await db.close();
  });

  test('foreign keys are enforced (pragma enabled in beforeOpen)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    // conversationId 999 doesn't exist -> FK violation.
    await expectLater(
      () => db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: 999,
              role: MessageRole.user,
              status: MessageStatus.complete,
              createdAt: DateTime.now(),
            ),
          ),
      throwsA(anything),
    );
    await db.close();
  });
}
