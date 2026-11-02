import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// `test/fixtures/db/v6.sqlite` is a REAL v6 database written by the shipped
/// v6 `AppDatabase` (a conversation, a message, an attached document with a
/// chunk). Each test opens a private copy with the current (v7) schema.
void main() {
  late Directory tempDir;
  late File file;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dhruva_connectors_mig');
    file = File(p.join(tempDir.path, 'v6.sqlite'));
    File('test/fixtures/db/v6.sqlite').copySync(file.path);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('fixture really is v6 (user_version lives at header offset 60)', () {
    final header = file.readAsBytesSync().sublist(60, 64);
    expect(ByteData.sublistView(header).getUint32(0), 6);
  });

  test(
    'v6 -> v7 keeps every existing row and adds the connector tables',
    () async {
      final db = AppDatabase(NativeDatabase(file));
      expect(db.schemaVersion, 9);

      // Existing chat + document data survives untouched.
      final convos = await db.select(db.conversations).get();
      expect(convos.single.title, 'Trip plan');
      final msgs = await db.select(db.messages).get();
      expect(msgs.single.content, 'Plan a trip to Pune');
      expect(await db.select(db.documentChunks).get(), hasLength(1));

      expect(
        db.allTables.map((t) => t.actualTableName),
        containsAll(['connector_accounts', 'items', 'ledger']),
      );
      final real = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('connector_accounts', 'items', 'ledger')",
          )
          .get();
      expect(real, hasLength(3));
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 9);

      // The new tables work.
      final now = DateTime.utc(2026, 11, 1, 8);
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              source: 'calendar',
              externalId: 'e1',
              kind: ItemKind.event,
              updatedAt: now,
            ),
          );
      expect((await db.select(db.items).getSingle()).kind, ItemKind.event);
      await db.close();
    },
  );

  test('v6 -> v8 also adds the Library tables, empty and working', () async {
    final db = AppDatabase(NativeDatabase(file));
    final real = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('saved_answers', 'todos')",
        )
        .get();
    expect(real, hasLength(2));
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            task: 'Pay rent',
            createdAt: DateTime.utc(2026, 11, 1),
          ),
        );
    final todo = await db.select(db.todos).getSingle();
    expect(todo.done, isFalse);
    // Existing data still intact.
    expect((await db.select(db.conversations).getSingle()).title, 'Trip plan');
    await db.close();
  });

  test('(source, externalId) is unique; the same id in another source is not '
      'a clash', () async {
    final db = AppDatabase(NativeDatabase(file));
    final now = DateTime.utc(2026, 11, 1, 8);
    ItemsCompanion row(String source) => ItemsCompanion.insert(
      source: source,
      externalId: 'same',
      kind: ItemKind.event,
      updatedAt: now,
    );
    await db.into(db.items).insert(row('calendar'));
    await db.into(db.items).insert(row('notifications'));
    await expectLater(
      db.into(db.items).insert(row('calendar')),
      throwsA(isA<SqliteException>()),
    );
    await db.close();
  });

  test('a fresh install gets the same connector schema and indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final idx = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name IN ('idx_items_kind_starts', 'idx_ledger_connector_at')",
        )
        .get();
    expect(idx, hasLength(2));
    await db.close();
  });

  test(
    'upgraded and fresh databases have identical connector indexes',
    () async {
      final upgraded = AppDatabase(NativeDatabase(file));
      final fresh = AppDatabase(NativeDatabase.memory());
      Future<List<String>> names(AppDatabase d) async =>
          (await d
                  .customSelect(
                    'SELECT name FROM sqlite_master WHERE tbl_name IN '
                    "('items', 'ledger', 'connector_accounts') ORDER BY name",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toList();
      expect(await names(upgraded), await names(fresh));
      await upgraded.close();
      await fresh.close();
    },
  );
}
