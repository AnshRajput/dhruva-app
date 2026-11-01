/// Library persistence: replies the user saved and to-dos they added. Plain
/// classes out (ADR-002: no drift types in features). Everything is local.
library;

import 'package:drift/drift.dart';

import '../db/database.dart';

final class SavedAnswer {
  final int id;
  final String content;
  final int? conversationId;
  final DateTime createdAt;
  const SavedAnswer({
    required this.id,
    required this.content,
    required this.conversationId,
    required this.createdAt,
  });

  /// First non-empty line, for the list row.
  String get headline {
    for (final l in content.split('\n')) {
      final t = l.replaceAll(RegExp(r'[#*_`>]+'), '').trim();
      if (t.isNotEmpty) return t;
    }
    return content.trim();
  }
}

final class TodoItem {
  final int id;
  final String text;
  final bool done;
  final DateTime createdAt;
  const TodoItem({
    required this.id,
    required this.text,
    required this.done,
    required this.createdAt,
  });
}

class LibraryStore {
  LibraryStore({required AppDatabase db, DateTime Function()? clock})
    : _db = db,
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  // ---- saved answers -------------------------------------------------------

  /// Keeps [content]. Saving the same text twice keeps one copy.
  Future<int> saveAnswer(String content, {int? conversationId}) async {
    final text = content.trim();
    if (text.isEmpty) throw ArgumentError('Nothing to save.');
    final dup = await (_db.select(
      _db.savedAnswers,
    )..where((t) => t.content.equals(text))).getSingleOrNull();
    if (dup != null) return dup.id;
    return _db
        .into(_db.savedAnswers)
        .insert(
          SavedAnswersCompanion.insert(
            content: text,
            conversationId: Value(conversationId),
            createdAt: _clock(),
          ),
        );
  }

  Stream<List<SavedAnswer>> watchSaved() {
    final q = _db.select(_db.savedAnswers)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          SavedAnswer(
            id: r.id,
            content: r.content,
            conversationId: r.conversationId,
            createdAt: r.createdAt,
          ),
      ],
    );
  }

  Future<void> deleteSaved(int id) =>
      (_db.delete(_db.savedAnswers)..where((t) => t.id.equals(id))).go();

  // ---- to-dos --------------------------------------------------------------

  /// Adds [texts] as open to-dos, skipping any that already exist as an open
  /// one. Returns how many were added.
  Future<int> addTodos(List<String> texts) => _db.transaction(() async {
    final open = {
      for (final t in await (_db.select(
        _db.todos,
      )..where((t) => t.done.equals(false))).get())
        t.task,
    };
    var added = 0;
    for (final raw in texts) {
      final text = raw.trim();
      if (text.isEmpty || !open.add(text)) continue;
      await _db
          .into(_db.todos)
          .insert(TodosCompanion.insert(task: text, createdAt: _clock()));
      added++;
    }
    return added;
  });

  /// Open ones first (oldest first), then done.
  Stream<List<TodoItem>> watchTodos() {
    final q = _db.select(_db.todos)
      ..orderBy([
        (t) => OrderingTerm.asc(t.done),
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          TodoItem(
            id: r.id,
            text: r.task,
            done: r.done,
            createdAt: r.createdAt,
          ),
      ],
    );
  }

  Future<void> setTodoDone(int id, bool done) => (_db.update(
    _db.todos,
  )..where((t) => t.id.equals(id))).write(TodosCompanion(done: Value(done)));

  Future<void> deleteTodo(int id) =>
      (_db.delete(_db.todos)..where((t) => t.id.equals(id))).go();

  Future<void> clearDoneTodos() =>
      (_db.delete(_db.todos)..where((t) => t.done.equals(true))).go();
}
