/// Library persistence: replies the user saved and to-dos they added. Plain
/// classes out (ADR-002: no drift types in features). Everything is local.
library;

import 'dart:convert';

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

/// The rule for Library items that quote connector data (M6):
///  - a saved answer / to-do records which connectors its source conversation
///    cited at the moment it was saved ([connectorsCitedBy]);
///  - revoking a connector deletes every saved answer and to-do that cites it
///    (`ConnectorStore.wipeConnector`, same transaction);
///  - "Clear all chat history" deletes every saved answer and to-do that cites
///    any connector (`ChatRepository.clearAllHistory`);
///  - items that cite no connector data are never touched by either.
/// Stored as `,calendar,notifications,` so one connector is a plain LIKE.
String encodeConnectors(Iterable<String> ids) {
  final sorted = ({...ids}..removeWhere((e) => e.isEmpty)).toList()..sort();
  return sorted.isEmpty ? '' : ',${sorted.join(',')},';
}

class LibraryStore {
  LibraryStore({required AppDatabase db, DateTime Function()? clock})
    : _db = db,
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  // ---- saved answers -------------------------------------------------------

  /// Which connectors the messages of [conversationId] cited (their stored
  /// item sources). Empty for no conversation or one without connector data.
  Future<Set<String>> connectorsCitedBy(int? conversationId) async {
    if (conversationId == null) return const {};
    final rows =
        await (_db.select(_db.messages)..where(
              (t) =>
                  t.conversationId.equals(conversationId) &
                  t.sourcesJson.isNotNull(),
            ))
            .get();
    final out = <String>{};
    for (final r in rows) {
      final raw = r.sourcesJson;
      if (raw == null) continue;
      try {
        final list = jsonDecode(raw);
        if (list is! List) continue;
        for (final e in list) {
          if (e is Map && e['k'] == 'item' && e['src'] is String) {
            out.add(e['src'] as String);
          }
        }
      } catch (_) {
        // A malformed citation list cites nothing.
      }
    }
    return out;
  }

  /// Keeps [content]. Saving the same text twice keeps one copy: the unique
  /// index on `content` makes a double-tap (or two racing saves) a no-op, and
  /// the insert never throws or leaves two rows behind.
  Future<int> saveAnswer(String content, {int? conversationId}) async {
    final text = content.trim();
    if (text.isEmpty) throw ArgumentError('Nothing to save.');
    final connectors = encodeConnectors(
      await connectorsCitedBy(conversationId),
    );
    return _db.transaction(() async {
      await _db
          .into(_db.savedAnswers)
          .insert(
            SavedAnswersCompanion.insert(
              content: text,
              conversationId: Value(conversationId),
              createdAt: _clock(),
              sourceConnectors: Value(connectors),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return (await (_db.select(
        _db.savedAnswers,
      )..where((t) => t.content.equals(text))).getSingle()).id;
    });
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
  /// one. Returns how many were added. [conversationId] is the chat the reply
  /// came from, so the to-dos know which connector data they quote.
  Future<int> addTodos(List<String> texts, {int? conversationId}) async {
    final connectors = encodeConnectors(
      await connectorsCitedBy(conversationId),
    );
    return _addTodos(texts, connectors);
  }

  Future<int> _addTodos(List<String> texts, String connectors) =>
      _db.transaction(() async {
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
              .insert(
                TodosCompanion.insert(
                  task: text,
                  createdAt: _clock(),
                  sourceConnectors: Value(connectors),
                ),
              );
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
