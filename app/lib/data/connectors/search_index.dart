/// Keyword search over everything the connectors stored (`items`), behind one
/// interface with two engines chosen ONCE at startup by [openSearchIndex]:
///
///  * [Fts5SearchIndex]: SQLite FTS5 with `bm25()` ranking, kept in step with
///    `items` by triggers (no application code has to remember to index).
///  * [Bm25FallbackSearchIndex]: when the SQLite build has no FTS5, a SQL
///    `LIKE` prefilter (capped at [fallbackCandidateCap] rows) feeds the same
///    pure-Dart BM25 ranker doc chat uses (`data/docs/bm25.dart`).
///
/// Drift 2.34.2 has no first-class FTS5 DSL (see `chat_repository.dart`), so
/// the virtual table and triggers are raw SQL on the app connection.
library;

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../docs/bm25.dart';
import 'connector.dart';
import 'connector_store.dart';

/// One ranked match.
final class SearchHit {
  final ConnectorItem item;

  /// Higher is better. Comparable only within one result list.
  final double score;
  const SearchHit(this.item, this.score);
}

abstract interface class SearchIndex {
  /// `fts5` or `bm25` (the fallback). For diagnostics and tests.
  String get engine;

  /// Best matches for [query], best first. Empty when the query has no usable
  /// keywords. [sources] / [kinds] narrow the search (null = everything).
  Future<List<SearchHit>> search(
    String query, {
    int limit = 20,
    Set<String>? sources,
    Set<ItemKind>? kinds,
  });
}

/// Most rows the fallback ranks per query.
const fallbackCandidateCap = 2000;

/// Most keywords one query uses.
const _maxTerms = 12;

/// Picks the engine once: FTS5 if the probe succeeds (or [forceFallback] is
/// false), otherwise the BM25 fallback. [forceFallback] exists for tests and
/// as a kill switch.
Future<SearchIndex> openSearchIndex(
  AppDatabase db,
  ConnectorStore store, {
  bool forceFallback = false,
}) async {
  if (!forceFallback && await _tryEnableFts5(db)) {
    return Fts5SearchIndex._(db, store);
  }
  await _dropFts5(db);
  return Bm25FallbackSearchIndex(db, store);
}

Future<bool> _tryEnableFts5(AppDatabase db) async {
  try {
    final existed = await db
        .customSelect("SELECT 1 FROM sqlite_master WHERE name = 'items_fts'")
        .get();
    await db.customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5('
      'title, body, summary, content=\'items\', content_rowid=\'id\', '
      "tokenize='unicode61 remove_diacritics 2')",
    );
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS items_fts_ai AFTER INSERT ON items BEGIN '
      'INSERT INTO items_fts(rowid, title, body, summary) '
      'VALUES (new.id, new.title, new.body, new.summary); END',
    );
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS items_fts_ad AFTER DELETE ON items BEGIN '
      'INSERT INTO items_fts(items_fts, rowid, title, body, summary) '
      "VALUES ('delete', old.id, old.title, old.body, old.summary); END",
    );
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS items_fts_au AFTER UPDATE ON items BEGIN '
      'INSERT INTO items_fts(items_fts, rowid, title, body, summary) '
      "VALUES ('delete', old.id, old.title, old.body, old.summary); "
      'INSERT INTO items_fts(rowid, title, body, summary) '
      'VALUES (new.id, new.title, new.body, new.summary); END',
    );
    if (existed.isEmpty) {
      // Index whatever `items` already holds (first run after the upgrade).
      await db.customStatement(
        "INSERT INTO items_fts(items_fts) VALUES ('rebuild')",
      );
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Without FTS5 the triggers must not exist: they would make every write to
/// `items` fail with "no such module: fts5".
Future<void> _dropFts5(AppDatabase db) async {
  for (final t in const ['items_fts_ai', 'items_fts_ad', 'items_fts_au']) {
    try {
      await db.customStatement('DROP TRIGGER IF EXISTS $t');
    } catch (_) {}
  }
  try {
    await db.customStatement('DROP TABLE IF EXISTS items_fts');
  } catch (_) {}
}

String _inList(Iterable<String> values) => values.map((_) => '?').join(', ');

/// Shared `WHERE` tail + variables for the source/kind filters.
({String sql, List<Variable> vars}) _filters(
  Set<String>? sources,
  Set<ItemKind>? kinds,
) {
  final sql = StringBuffer();
  final vars = <Variable>[];
  if (sources != null && sources.isNotEmpty) {
    sql.write(' AND items.source IN (${_inList(sources)})');
    vars.addAll(sources.map(Variable.withString));
  }
  if (kinds != null && kinds.isNotEmpty) {
    sql.write(' AND items.kind IN (${_inList(kinds.map((k) => k.name))})');
    vars.addAll(kinds.map((k) => Variable.withString(k.name)));
  }
  return (sql: sql.toString(), vars: vars);
}

List<String> _terms(String query) {
  final seen = <String>{};
  for (final t in tokenize(query)) {
    seen.add(t);
    if (seen.length == _maxTerms) break;
  }
  return seen.toList();
}

final class Fts5SearchIndex implements SearchIndex {
  Fts5SearchIndex._(this._db, this._store);

  final AppDatabase _db;
  final ConnectorStore _store;

  @override
  String get engine => 'fts5';

  @override
  Future<List<SearchHit>> search(
    String query, {
    int limit = 20,
    Set<String>? sources,
    Set<ItemKind>? kinds,
  }) async {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];
    // Terms hold only letters/digits (see tokenize), so quoting is enough.
    final match = terms.map((t) => '"$t"*').join(' OR ');
    final f = _filters(sources, kinds);
    final rows = await _db
        .customSelect(
          'SELECT items.*, bm25(items_fts, 4.0, 1.0, 2.0) AS rank '
          'FROM items_fts JOIN items ON items.id = items_fts.rowid '
          'WHERE items_fts MATCH ?${f.sql} ORDER BY rank LIMIT ?',
          variables: [
            Variable.withString(match),
            ...f.vars,
            Variable.withInt(limit),
          ],
          readsFrom: {_db.items},
        )
        .get();
    return [
      for (final r in rows)
        SearchHit(
          _store.itemFromRow(_db.items.map(r.data)),
          -r.read<double>('rank'),
        ),
    ];
  }
}

final class Bm25FallbackSearchIndex implements SearchIndex {
  Bm25FallbackSearchIndex(this._db, this._store);

  final AppDatabase _db;
  final ConnectorStore _store;

  @override
  String get engine => 'bm25';

  @override
  Future<List<SearchHit>> search(
    String query, {
    int limit = 20,
    Set<String>? sources,
    Set<ItemKind>? kinds,
  }) async {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];
    final f = _filters(sources, kinds);

    // ponytail: SQLite LIKE only case-folds ASCII, so a non-ASCII term would
    // miss "Ünal" for "ünal". When any term is non-ASCII the prefilter is
    // skipped and the 2,000 newest rows are ranked instead. Upgrade path: an
    // ICU-free fold column if the fallback ever matters in practice.
    final ascii = terms.every((t) => t.codeUnits.every((c) => c < 128));
    final where = StringBuffer('1 = 1');
    final vars = <Variable>[];
    if (ascii) {
      where.write(' AND (');
      for (var i = 0; i < terms.length; i++) {
        if (i > 0) where.write(' OR ');
        where.write(
          "items.title LIKE ? ESCAPE '\\' OR items.body LIKE ? ESCAPE '\\' "
          "OR items.summary LIKE ? ESCAPE '\\'",
        );
        final pat = '%${_likeEscape(terms[i])}%';
        vars.addAll([
          Variable.withString(pat),
          Variable.withString(pat),
          Variable.withString(pat),
        ]);
      }
      where.write(')');
    }
    where.write(f.sql);
    vars.addAll(f.vars);

    final rows = await _db
        .customSelect(
          'SELECT items.* FROM items WHERE $where '
          'ORDER BY items.updated_at DESC LIMIT $fallbackCandidateCap',
          variables: vars,
          readsFrom: {_db.items},
        )
        .get();
    if (rows.isEmpty) return const [];
    final items = [
      for (final r in rows) _store.itemFromRow(_db.items.map(r.data)),
    ];
    // Title counts double, like the FTS column weights.
    final index = Bm25Index([
      for (final i in items)
        '${i.title} ${i.title} ${i.body} ${i.summary ?? ''}',
    ]);
    return [
      for (final s in index.search(query).take(limit))
        SearchHit(items[s.index], s.score),
    ];
  }
}

String _likeEscape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
