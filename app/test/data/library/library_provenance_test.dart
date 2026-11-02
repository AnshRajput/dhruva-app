// M6 + M7: Library items that quote connector data go when that data goes,
// and saving the same reply twice (or at the same time) keeps one row.

import 'dart:io';

import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/connectors/ask_sources.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/library/library_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late LibraryStore library;
  late ChatRepository chats;
  late ConnectorStore connectors;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(db: db);
    chats = ChatRepository(db: db);
    connectors = ConnectorStore(db: db);
  });
  tearDown(() => db.close());

  /// A conversation whose reply cites items of [cited] connectors.
  Future<int> chatCiting(List<String> cited) async {
    final c = await chats.createConversation();
    await chats.appendMessage(
      conversationId: c,
      role: MessageRole.user,
      content: 'q',
    );
    final reply = await chats.appendMessage(
      conversationId: c,
      role: MessageRole.assistant,
      content: 'a',
    );
    if (cited.isNotEmpty) {
      await chats.setSources(
        reply,
        const [],
        items: [
          for (var i = 0; i < cited.length; i++)
            ItemSource(
              itemId: i + 1,
              source: cited[i],
              kind: ItemKind.event,
              label: 'x',
            ),
        ],
      );
    }
    return c;
  }

  group('M7: saveAnswer', () {
    test('racing saves of one text keep one row and both get its id', () async {
      final ids = await Future.wait([
        library.saveAnswer('Same reply'),
        library.saveAnswer('Same reply'),
        library.saveAnswer(' Same reply '),
      ]);
      expect(ids.toSet(), hasLength(1));
      expect(await db.select(db.savedAnswers).get(), hasLength(1));
      // And it keeps working afterwards (no StateError on a second lookup).
      expect(await library.saveAnswer('Same reply'), ids.first);
    });

    test('the unique index exists on a fresh install', () async {
      final idx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_saved_answers_content'",
          )
          .get();
      expect(idx, hasLength(1));
    });

    test('v8 -> v9 collapses existing duplicates and adds the column', () async {
      final dir = Directory.systemTemp.createTempSync('dhruva_lib_mig');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'v8.sqlite'));
      final old = AppDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            raw.execute(
              'CREATE TABLE saved_answers (id INTEGER PRIMARY KEY '
              'AUTOINCREMENT, content TEXT NOT NULL, conversation_id INTEGER, '
              'created_at INTEGER NOT NULL)',
            );
            raw.execute(
              'CREATE TABLE todos (id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'task TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0, '
              'created_at INTEGER NOT NULL)',
            );
            for (final t in ['dup', 'dup', 'one']) {
              raw.execute(
                "INSERT INTO saved_answers (content, created_at) VALUES "
                "('$t', 1)",
              );
            }
            raw.execute("INSERT INTO todos (task, created_at) VALUES ('t', 1)");
            raw.execute('PRAGMA user_version = 8');
          },
        ),
      );
      final rows = await old.select(old.savedAnswers).get();
      expect(rows.map((r) => r.content), unorderedEquals(['dup', 'one']));
      expect(rows.every((r) => r.sourceConnectors == ''), isTrue);
      expect((await old.select(old.todos).getSingle()).sourceConnectors, '');
      await old.close();
    });
  });

  group('M6: derived Library items follow their connector data', () {
    test(
      'what a save records: the connectors its conversation cited',
      () async {
        final chat = await chatCiting(['calendar', 'notifications']);
        await library.saveAnswer('Meeting at 3', conversationId: chat);
        await library.addTodos(['Reply to Sana'], conversationId: chat);
        final saved = await db.select(db.savedAnswers).getSingle();
        expect(saved.sourceConnectors, ',calendar,notifications,');
        expect(
          (await db.select(db.todos).getSingle()).sourceConnectors,
          ',calendar,notifications,',
        );
        final plain = await chatCiting([]);
        await library.saveAnswer('Plain', conversationId: plain);
        await library.saveAnswer('No chat');
        expect(
          (await (db.select(
                db.savedAnswers,
              )..where((t) => t.content.equals('Plain'))).getSingle())
              .sourceConnectors,
          '',
        );
      },
    );

    test('revoking a connector deletes only the items that cite it', () async {
      final cal = await chatCiting(['calendar']);
      final both = await chatCiting(['calendar', 'contacts']);
      final contacts = await chatCiting(['contacts']);
      final none = await chatCiting([]);
      await library.saveAnswer('from cal', conversationId: cal);
      await library.saveAnswer('from both', conversationId: both);
      await library.saveAnswer('from contacts', conversationId: contacts);
      await library.saveAnswer('from none', conversationId: none);
      await library.addTodos(['cal todo'], conversationId: cal);
      await library.addTodos(['none todo'], conversationId: none);

      await connectors.wipeConnector('calendar');

      final saved = [
        for (final s in await db.select(db.savedAnswers).get()) s.content,
      ];
      expect(saved, unorderedEquals(['from contacts', 'from none']));
      final todos = [for (final t in await db.select(db.todos).get()) t.task];
      expect(todos, ['none todo']);
    });

    test('Clear all chat history deletes connector-derived items, keeps the '
        'rest', () async {
      final cal = await chatCiting(['notifications']);
      final none = await chatCiting([]);
      await library.saveAnswer('derived', conversationId: cal);
      await library.saveAnswer('mine', conversationId: none);
      await library.addTodos(['derived todo'], conversationId: cal);
      await library.addTodos(['my todo']);

      await chats.clearAllHistory();

      expect(await db.select(db.conversations).get(), isEmpty);
      expect(
        [for (final s in await db.select(db.savedAnswers).get()) s.content],
        ['mine'],
      );
      expect(
        [for (final t in await db.select(db.todos).get()) t.task],
        ['my todo'],
      );
    });
  });
}
