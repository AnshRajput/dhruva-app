import 'dart:io';

import 'package:dhruva/data/db/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Behaves like the shipped v5 schema: no `attached_documents` /
/// `document_chunks` tables and no `messages.sources_json` column
/// (createTable-then-DROP-COLUMN, same trick as `report_migration_test.dart`
/// — there are no schema snapshots to diff).
class _V5Database extends AppDatabase {
  _V5Database(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createTable(installedModels);
      await m.createTable(folders);
      await m.createTable(conversations);
      await m.createTable(messages);
      await m.createTable(characters);
      await m.createTable(contentReports);
      await customStatement('ALTER TABLE messages DROP COLUMN sources_json');
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
    tempDir = Directory.systemTemp.createTempSync('dhruva_docs_migration');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('v5 -> v6 keeps messages, adds sources_json and the document tables '
      '(with working cascade)', () async {
    final file = File(p.join(tempDir.path, 'v5.sqlite'));
    final v5 = _V5Database(NativeDatabase(file));
    final now = DateTime.utc(2026, 10, 1);
    final convoId = await v5
        .into(v5.conversations)
        .insert(ConversationsCompanion.insert(createdAt: now, updatedAt: now));
    await v5.customStatement(
      'INSERT INTO messages (conversation_id, role, content, status, '
      'reported, created_at) VALUES ($convoId, 1, \'hello\', 0, 0, 0)',
    );
    await v5.close();

    final v6 = AppDatabase(NativeDatabase(file));
    expect(v6.schemaVersion, 6);

    // Existing data survives; the new column defaults to null.
    final rows = await v6.select(v6.messages).get();
    expect(rows, hasLength(1));
    expect(rows.single.content, 'hello');
    expect(rows.single.sourcesJson, isNull);
    await (v6.update(
      v6.messages,
    )).write(const MessagesCompanion(sourcesJson: Value('[]')));

    // The new tables exist and work, and the FK chain cascades:
    // conversation -> attached_documents -> document_chunks.
    final docId = await v6
        .into(v6.attachedDocuments)
        .insert(
          AttachedDocumentsCompanion.insert(
            conversationId: convoId,
            name: 'a.pdf',
            mime: 'application/pdf',
            pageCount: const Value(2),
            charCount: const Value(900),
            createdAt: now,
          ),
        );
    await v6
        .into(v6.documentChunks)
        .insert(
          DocumentChunksCompanion.insert(
            documentId: docId,
            chunkIndex: 0,
            page: 1,
            body: 'chunk text',
          ),
        );
    expect(await v6.select(v6.documentChunks).get(), hasLength(1));

    await (v6.delete(v6.conversations)).go();
    expect(await v6.select(v6.attachedDocuments).get(), isEmpty);
    expect(await v6.select(v6.documentChunks).get(), isEmpty);
    await v6.close();
  });

  test(
    'the chunk lookup index exists after upgrade and on a fresh DB',
    () async {
      final file = File(p.join(tempDir.path, 'v5b.sqlite'));
      final v5 = _V5Database(NativeDatabase(file));
      await v5.customStatement('SELECT 1'); // force onCreate
      await v5.close();

      for (final db in [
        AppDatabase(NativeDatabase(file)),
        AppDatabase(NativeDatabase.memory()),
      ]) {
        final idx = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND name = 'idx_document_chunks_document'",
            )
            .get();
        expect(idx, hasLength(1));
        expect(
          db.allTables.map((t) => t.actualTableName),
          containsAll(['attached_documents', 'document_chunks']),
        );
        await db.close();
      }
    },
  );
}
