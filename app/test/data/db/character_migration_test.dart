import 'dart:io';

import 'package:dhruva/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Behaves exactly like the real shipped v2 schema (pre-Loop-5): every
/// table `chat_migration_test.dart`'s v1->v2 test already covers, but
/// `conversations` WITHOUT the new `character_id` column, and no
/// `characters` table.
///
/// Built via the real (current) generated DDL for every table — via
/// `m.createTable`, so column types/encodings are exactly what drift would
/// really produce — then `ALTER TABLE ... DROP COLUMN` removes the one
/// column that didn't exist yet at v2. That's the only manually-reasoned
/// SQL here, versus hand-writing the whole table (this codebase has no
/// schema-snapshot codegen to diff against — see build.yaml's doc comment
/// on why `db.managers` was removed — so this is the same trick used
/// nowhere else yet, but the least error-prone option available).
class _V2Database extends AppDatabase {
  _V2Database(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createTable(installedModels);
      await m.createTable(folders);
      await m.createTable(conversations);
      await m.createTable(messages);
      await customStatement(
        'ALTER TABLE conversations DROP COLUMN character_id',
      );
      // Same "createTable always builds the CURRENT shape" trick as above,
      // now for `installed_models`'s Loop-7 mmproj_path/is_vision columns
      // (didn't exist at v2) — see chat_migration_test.dart's `_V1Database`
      // for the same fix, needed for the same reason.
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
    tempDir = Directory.systemTemp.createTempSync('dhruva_character_migration');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('v2 -> v3 migration preserves existing conversations/messages and adds '
      'the characters table + conversations.character_id', () async {
    final dbFile = File(p.join(tempDir.path, 'v2.sqlite'));

    final v2 = _V2Database(NativeDatabase(dbFile));
    expect(v2.schemaVersion, 2);
    final now = DateTime.utc(2026, 7, 17);
    final conversationId = await v2
        .into(v2.conversations)
        .insert(
          ConversationsCompanion.insert(
            title: const Value('Existing thread'),
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
            content: const Value('hello from before the migration'),
            status: MessageStatus.complete,
            createdAt: now,
          ),
        );
    await v2.close();

    // Reopen with the real (current, v4) AppDatabase over the same file —
    // this must trigger the real onUpgrade(2, 4), running both the v2->v3
    // and v3->v4 branches in one jump.
    final v3 = AppDatabase(NativeDatabase(dbFile));
    expect(v3.schemaVersion, 4);

    final conversations = await v3.select(v3.conversations).get();
    expect(conversations, hasLength(1));
    expect(conversations.single.id, conversationId);
    expect(conversations.single.title, 'Existing thread');
    expect(conversations.single.characterId, null); // new column, unset

    final messages = await v3.select(v3.messages).get();
    expect(messages, hasLength(1));
    expect(messages.single.content, 'hello from before the migration');

    // The new table is usable post-migration, and the new FK column can
    // now be set to point an old conversation at a new character.
    final characterId = await v3
        .into(v3.characters)
        .insert(
          CharactersCompanion.insert(
            name: 'Coach',
            personaSystemPrompt: 'You are an encouraging coach.',
            isBuiltIn: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await (v3.update(v3.conversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsCompanion(characterId: Value(characterId)));
    final updated = await (v3.select(
      v3.conversations,
    )..where((t) => t.id.equals(conversationId))).getSingle();
    expect(updated.characterId, characterId);

    // Deleting the character un-sets characterId (ON DELETE SET NULL),
    // same "survives deletion" precedent as modelId/folderId.
    await (v3.delete(
      v3.characters,
    )..where((t) => t.id.equals(characterId))).go();
    final afterDelete = await (v3.select(
      v3.conversations,
    )..where((t) => t.id.equals(conversationId))).getSingle();
    expect(afterDelete.characterId, null);

    await v3.close();
  });

  test('a fresh v3 database has the characters table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.allTables.map((t) => t.actualTableName), contains('characters'));
    await db.close();
  });
}
