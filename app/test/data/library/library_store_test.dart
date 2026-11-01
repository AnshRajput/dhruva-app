// Wave 3B: Library persistence (saved answers, to-dos) and the conservative
// to-do parser for the "Extract to-dos" action output.

import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/library/library_store.dart';
import 'package:dhruva/data/library/todo_parser.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTodos', () {
    test('the action\'s own format: "- [ ]" lines, who and when kept', () {
      const reply =
          '- [ ] Send revised invoice to Sofia\n'
          '- [ ] Confirm Goa dates with Marcus by Wednesday\n'
          '- [x] Book lunch table, Social';
      expect(parseTodos(reply), [
        'Send revised invoice to Sofia',
        'Confirm Goa dates with Marcus by Wednesday',
      ]);
    });

    test('"No action items." and empty text give nothing', () {
      expect(parseTodos('No action items.'), isEmpty);
      expect(parseTodos('- [ ] No action items.'), isEmpty);
      expect(parseTodos('   \n  '), isEmpty);
    });

    test('plain bullets count only when the whole reply is a list', () {
      expect(parseTodos('- call mum\n- pay rent\n* buy milk'), [
        'call mum',
        'pay rent',
        'buy milk',
      ]);
      expect(parseTodos('1. call mum\n2) pay rent'), ['call mum', 'pay rent']);
      // One intro line ending in a colon is allowed.
      expect(parseTodos('Here are the tasks:\n- call mum\n- pay rent'), [
        'call mum',
        'pay rent',
      ]);
    });

    test('prose with a bullet in it is not a task list', () {
      const advice =
          'Here is some advice about your week. You could do many things.\n'
          '- drink water\n'
          'Remember to rest.';
      expect(parseTodos(advice), isEmpty);
      expect(parseTodos('Just a sentence.'), isEmpty);
    });

    test('dedupes, strips emphasis, caps count and length', () {
      expect(parseTodos('- [ ] **Pay** rent\n- [ ] Pay rent'), ['Pay rent']);
      final many = [for (var i = 0; i < 40; i++) '- [ ] task $i'].join('\n');
      expect(parseTodos(many), hasLength(maxTodosPerReply));
      final long = parseTodos('- [ ] ${'x' * 500}').single;
      expect(long.length, maxTodoChars);
      expect(long.endsWith('…'), isTrue);
    });
  });

  group('LibraryStore', () {
    late AppDatabase db;
    late LibraryStore store;
    var tick = 0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      tick = 0;
      store = LibraryStore(
        db: db,
        clock: () => DateTime.utc(2026, 11, 1, 8, tick++),
      );
    });
    tearDown(() => db.close());

    test('saved answers: newest first, de-duplicated, deletable', () async {
      final a = await store.saveAnswer('First reply', conversationId: 4);
      final b = await store.saveAnswer('Second reply\n\nmore');
      expect(await store.saveAnswer('  First reply  '), a, reason: 'dedupe');
      final list = await store.watchSaved().first;
      expect([for (final s in list) s.id], [b, a]);
      expect(list.first.headline, 'Second reply');
      expect(list.last.conversationId, 4);
      await store.deleteSaved(a);
      expect((await store.watchSaved().first).map((s) => s.id), [b]);
      expect(() => store.saveAnswer('   '), throwsArgumentError);
    });

    test('to-dos: added, listed open first, checked off, deleted, '
        'persisted', () async {
      expect(await store.addTodos(['Pay rent', 'Call mum', '  ']), 2);
      // An open duplicate is skipped.
      expect(await store.addTodos(['Pay rent', 'Buy milk']), 1);
      var todos = await store.watchTodos().first;
      expect(
        [for (final t in todos) t.text],
        ['Pay rent', 'Call mum', 'Buy milk'],
      );
      await store.setTodoDone(todos.first.id, true);
      todos = await store.watchTodos().first;
      expect(
        [for (final t in todos) (t.text, t.done)],
        [('Call mum', false), ('Buy milk', false), ('Pay rent', true)],
      );
      // A done item may be added again (it is no longer open).
      expect(await store.addTodos(['Pay rent']), 1);
      await store.clearDoneTodos();
      todos = await store.watchTodos().first;
      expect(todos.map((t) => t.text), ['Call mum', 'Buy milk', 'Pay rent']);
      await store.deleteTodo(todos.first.id);
      expect((await store.watchTodos().first).length, 2);
    });
  });

  test('schema v8 creates the library tables on a fresh database', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 8);
    expect(await db.select(db.todos).get(), isEmpty);
    expect(await db.select(db.savedAnswers).get(), isEmpty);
  });
}
