import 'dart:io';

import 'package:dhruva/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Behaves like the shipped v4 schema: no `content_reports` table and no
/// `messages.reported` column (createTable-then-DROP-COLUMN, same trick as
/// `vision_migration_test.dart` — there are no schema snapshots to diff).
class _V4Database extends AppDatabase {
  _V4Database(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createTable(installedModels);
      await m.createTable(folders);
      await m.createTable(conversations);
      await m.createTable(messages);
      await m.createTable(characters);
      await customStatement('ALTER TABLE messages DROP COLUMN reported');
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
    tempDir = Directory.systemTemp.createTempSync('dhruva_report_migration');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('v4 -> v5 keeps messages, defaults reported to false, adds '
      'content_reports', () async {
    final file = File(p.join(tempDir.path, 'v4.sqlite'));
    final v4 = _V4Database(NativeDatabase(file));
    final now = DateTime.utc(2026, 10, 1);
    final convoId = await v4
        .into(v4.conversations)
        .insert(ConversationsCompanion.insert(createdAt: now, updatedAt: now));
    await v4.customStatement(
      'INSERT INTO messages (conversation_id, role, content, status, '
      'created_at) VALUES ($convoId, 1, \'hello\', 0, 0)',
    );
    await v4.close();

    final v5 = AppDatabase(NativeDatabase(file));
    expect(v5.schemaVersion, 5);
    final rows = await v5.select(v5.messages).get();
    expect(rows, hasLength(1));
    expect(rows.single.content, 'hello');
    expect(rows.single.reported, isFalse);

    final id = await v5
        .into(v5.contentReports)
        .insert(
          ContentReportsCompanion.insert(
            createdAt: now,
            conversationId: convoId,
            messageId: rows.single.id,
            reason: 'other',
            excerpt: 'hello',
          ),
        );
    expect(id, greaterThan(0));
    await v5.close();
  });

  test('a fresh database has content_reports and messages.reported', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(
      db.allTables.map((t) => t.actualTableName),
      contains('content_reports'),
    );
    await db.close();
  });
}
