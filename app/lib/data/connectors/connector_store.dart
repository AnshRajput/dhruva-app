/// The one place connector data is read and written: accounts, items, the
/// privacy ledger. Connectors never touch drift directly, and features read
/// plain [ConnectorItem]s from here (ADR-002).
///
/// Writes are idempotent: an item is keyed by (source, externalId), so a
/// re-sync updates in place. If the search engine is FTS5 its triggers (see
/// `search_index.dart`) keep the index in step with every write made here,
/// including the bulk delete on revoke.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'connector.dart';

/// How many items one upsert changed.
final class IngestResult {
  final int inserted;
  final int updated;
  final int unchanged;
  const IngestResult({this.inserted = 0, this.updated = 0, this.unchanged = 0});

  int get changed => inserted + updated;
}

/// Persisted standing of one connector (a `connector_accounts` row).
final class ConnectorAccount {
  final String connector;
  final String status;
  final String? label;
  final Map<String, Object?> config;
  final String? lastError;
  final DateTime connectedAt;
  final DateTime? lastSyncAt;

  const ConnectorAccount({
    required this.connector,
    required this.status,
    required this.label,
    required this.config,
    required this.lastError,
    required this.connectedAt,
    required this.lastSyncAt,
  });
}

/// Notifications from one app, newest first.
final class NotificationGroup {
  final String package;
  final String appLabel;
  final List<ConnectorItem> items;
  const NotificationGroup({
    required this.package,
    required this.appLabel,
    required this.items,
  });

  DateTime get latest => items.first.sentAt ?? items.first.updatedAt;
}

/// Cuts [s] to at most [max] UTF-16 units without splitting a surrogate pair.
String capText(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  final c = s.codeUnitAt(end - 1);
  if (c >= 0xD800 && c <= 0xDBFF) end--;
  return s.substring(0, end);
}

class ConnectorStore {
  ConnectorStore({required AppDatabase db, DateTime Function()? clock})
    : _db = db,
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  DateTime get now => _clock();

  // ---- items -------------------------------------------------------------

  /// Inserts new drafts and updates changed ones (matched on externalId),
  /// leaving identical rows alone. A changed title/body drops the cached
  /// summary because it no longer describes the text.
  Future<IngestResult> upsertItems(
    String source,
    List<ItemDraft> drafts,
  ) async {
    if (drafts.isEmpty) return const IngestResult();
    // Last draft wins if a connector repeats an id within one batch.
    final byId = <String, ItemDraft>{for (final d in drafts) d.externalId: d};
    var inserted = 0, updated = 0, unchanged = 0;
    await _db.transaction(() async {
      final existing = <String, ItemRow>{};
      final ids = byId.keys.toList();
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
        final rows =
            await (_db.select(_db.items)
                  ..where((t) => t.source.equals(source))
                  ..where((t) => t.externalId.isIn(chunk)))
                .get();
        for (final r in rows) {
          existing[r.externalId] = r;
        }
      }
      for (final d in byId.values) {
        final body = capText(d.body, maxItemBodyChars);
        final people = jsonEncode(d.people.map((p) => p.toJson()).toList());
        final flags = jsonEncode(d.flags);
        final old = existing[d.externalId];
        if (old == null) {
          await _db
              .into(_db.items)
              .insert(
                ItemsCompanion.insert(
                  source: source,
                  externalId: d.externalId,
                  kind: d.kind,
                  title: Value(d.title),
                  body: Value(body),
                  peopleJson: Value(people),
                  startsAt: Value(d.startsAt),
                  sentAt: Value(d.sentAt),
                  flagsJson: Value(flags),
                  updatedAt: now,
                ),
              );
          inserted++;
          continue;
        }
        final same =
            old.kind == d.kind &&
            old.title == d.title &&
            old.body == body &&
            old.peopleJson == people &&
            _sec(old.startsAt) == _sec(d.startsAt) &&
            _sec(old.sentAt) == _sec(d.sentAt) &&
            old.flagsJson == flags;
        if (same) {
          unchanged++;
          continue;
        }
        final textChanged = old.title != d.title || old.body != body;
        await (_db.update(_db.items)..where((t) => t.id.equals(old.id))).write(
          ItemsCompanion(
            kind: Value(d.kind),
            title: Value(d.title),
            body: Value(body),
            peopleJson: Value(people),
            startsAt: Value(d.startsAt),
            sentAt: Value(d.sentAt),
            flagsJson: Value(flags),
            summary: textChanged ? const Value(null) : const Value.absent(),
            summaryModel: textChanged
                ? const Value(null)
                : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
        updated++;
      }
    });
    return IngestResult(
      inserted: inserted,
      updated: updated,
      unchanged: unchanged,
    );
  }

  /// Deletes [source]'s items of [kind] that start in `[from, to]` and are not
  /// in [keep]: an event removed from the calendar must leave the store too.
  Future<int> removeMissingInWindow(
    String source,
    ItemKind kind, {
    required DateTime from,
    required DateTime to,
    required Set<String> keep,
  }) async {
    final rows =
        await (_db.select(_db.items)
              ..where((t) => t.source.equals(source))
              ..where((t) => t.kind.equalsValue(kind))
              ..where((t) => t.startsAt.isBiggerOrEqualValue(from))
              ..where((t) => t.startsAt.isSmallerOrEqualValue(to)))
            .get();
    final stale = [
      for (final r in rows)
        if (!keep.contains(r.externalId)) r.id,
    ];
    return _deleteIds(stale);
  }

  /// Deletes [source] items whose [ItemRow.externalId] is [prefix] or starts
  /// with `prefix#` (the sections of one file). Matched in Dart so the `%` and
  /// `_` in SAF uris are never treated as LIKE wildcards.
  Future<int> removeByIdPrefix(String source, String prefix) async {
    final rows = await (_db.select(
      _db.items,
    )..where((t) => t.source.equals(source))).get();
    final hit = [
      for (final r in rows)
        if (r.externalId == prefix || r.externalId.startsWith('$prefix#')) r.id,
    ];
    return _deleteIds(hit);
  }

  /// Deletes [source] items older than [cutoff] (by sentAt, else updatedAt).
  Future<int> pruneOlderThan(String source, DateTime cutoff) {
    return (_db.delete(_db.items)
          ..where((t) => t.source.equals(source))
          ..where(
            (t) =>
                t.sentAt.isSmallerThanValue(cutoff) |
                (t.sentAt.isNull() & t.updatedAt.isSmallerThanValue(cutoff)),
          ))
        .go();
  }

  Future<int> _deleteIds(List<int> ids) async {
    var n = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
      n += await (_db.delete(_db.items)..where((t) => t.id.isIn(chunk))).go();
    }
    return n;
  }

  Future<int> countItems(String source) async {
    final c = _db.items.id.count();
    final q = _db.selectOnly(_db.items)
      ..addColumns([c])
      ..where(_db.items.source.equals(source));
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// Stored items of one source (file sections need their mtime on re-index).
  Future<List<ConnectorItem>> itemsOf(String source, {ItemKind? kind}) async {
    final q = _db.select(_db.items)..where((t) => t.source.equals(source));
    if (kind != null) q.where((t) => t.kind.equalsValue(kind));
    return [for (final r in await q.get()) _toItem(r)];
  }

  Future<List<ConnectorItem>> itemsByIds(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];
    final rows = await (_db.select(
      _db.items,
    )..where((t) => t.id.isIn(list))).get();
    return [for (final r in rows) _toItem(r)];
  }

  /// A contact item whose people include [email] (case-insensitive), or null.
  Future<ConnectorItem?> contactForEmail(String email) async {
    final needle = email.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final rows =
        await (_db.select(_db.items)
              ..where((t) => t.source.equals(ConnectorIds.contacts))
              ..where((t) => t.kind.equalsValue(ItemKind.contact)))
            .get();
    for (final r in rows) {
      final item = _toItem(r);
      if (item.people.any((p) => p.email?.toLowerCase() == needle)) return item;
    }
    return null;
  }

  /// Writes a generated one-line summary (`summaryModel` records which model
  /// wrote it so a model switch can re-summarise).
  Future<void> setSummary(int itemId, String summary, String model) =>
      (_db.update(_db.items)..where((t) => t.id.equals(itemId))).write(
        ItemsCompanion(
          summary: Value(summary),
          summaryModel: Value(model),
          updatedAt: Value(now),
        ),
      );

  // ---- live queries ------------------------------------------------------

  /// Events that start on [now]'s local calendar day, earliest first.
  Stream<List<ConnectorItem>> watchTodaysEvents(DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _events(
      (t) =>
          t.startsAt.isBiggerOrEqualValue(start) &
          t.startsAt.isSmallerThanValue(end),
    );
  }

  /// The next [limit] events starting at or after [now].
  Stream<List<ConnectorItem>> watchNextEvents(DateTime now, {int limit = 2}) {
    return _events((t) => t.startsAt.isBiggerOrEqualValue(now), limit: limit);
  }

  Stream<List<ConnectorItem>> _events(
    Expression<bool> Function(Items t) where, {
    int? limit,
  }) {
    final q = _db.select(_db.items)
      ..where((t) => t.kind.equalsValue(ItemKind.event))
      ..where(where)
      ..orderBy([(t) => OrderingTerm.asc(t.startsAt)]);
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => [for (final r in rows) _toItem(r)]);
  }

  /// Notifications newer than [since], grouped by app, the app with the most
  /// recent notification first.
  Stream<List<NotificationGroup>> watchNotificationsByApp({DateTime? since}) {
    final q = _db.select(_db.items)
      ..where((t) => t.kind.equalsValue(ItemKind.notification))
      ..orderBy([(t) => OrderingTerm.desc(t.sentAt)]);
    if (since != null) q.where((t) => t.sentAt.isBiggerOrEqualValue(since));
    return q.watch().map(
      (rows) => groupNotifications([for (final r in rows) _toItem(r)]),
    );
  }

  Stream<List<LedgerEntry>> watchLedger({int limit = 200}) {
    final q = _db.select(_db.ledger)
      ..orderBy([
        (t) => OrderingTerm.desc(t.at),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    return q.watch().map((rows) => [for (final r in rows) _toEntry(r)]);
  }

  Future<List<LedgerEntry>> ledger({String? connector}) async {
    final q = _db.select(_db.ledger)
      ..orderBy([
        (t) => OrderingTerm.desc(t.at),
        (t) => OrderingTerm.desc(t.id),
      ]);
    if (connector != null) q.where((t) => t.connector.equals(connector));
    return [for (final r in await q.get()) _toEntry(r)];
  }

  // ---- ledger ------------------------------------------------------------

  Future<void> addLedger(String connector, String action, {int count = 0}) =>
      _db
          .into(_db.ledger)
          .insert(
            LedgerCompanion.insert(
              connector: connector,
              action: action,
              count: Value(count),
              at: now,
            ),
          );

  // ---- accounts ----------------------------------------------------------

  Future<ConnectorAccount?> account(String connector) async {
    final row = await (_db.select(
      _db.connectorAccounts,
    )..where((t) => t.connector.equals(connector))).getSingleOrNull();
    return row == null ? null : _toAccount(row);
  }

  Stream<List<ConnectorAccount>> watchAccounts() => _db
      .select(_db.connectorAccounts)
      .watch()
      .map((rows) => [for (final r in rows) _toAccount(r)]);

  /// Creates or updates the opt-in row. Only the given fields change.
  Future<void> saveAccount(
    String connector, {
    String? status,
    String? label,
    Map<String, Object?>? config,
    String? lastError,
    bool clearError = false,
    DateTime? lastSyncAt,
  }) async {
    final existing = await account(connector);
    if (existing == null) {
      await _db
          .into(_db.connectorAccounts)
          .insert(
            ConnectorAccountsCompanion.insert(
              connector: connector,
              status: status ?? 'connected',
              label: Value(label),
              configJson: Value(config == null ? null : jsonEncode(config)),
              lastError: Value(lastError),
              connectedAt: now,
              lastSyncAt: Value(lastSyncAt),
            ),
          );
      return;
    }
    await (_db.update(
      _db.connectorAccounts,
    )..where((t) => t.connector.equals(connector))).write(
      ConnectorAccountsCompanion(
        status: status == null ? const Value.absent() : Value(status),
        label: label == null ? const Value.absent() : Value(label),
        configJson: config == null
            ? const Value.absent()
            : Value(jsonEncode(config)),
        lastError: clearError
            ? const Value(null)
            : (lastError == null ? const Value.absent() : Value(lastError)),
        lastSyncAt: lastSyncAt == null
            ? const Value.absent()
            : Value(lastSyncAt),
      ),
    );
  }

  /// Revoke: deletes the connector's items (and so its FTS rows), its content
  /// ledger rows and its account row, then records one `revoke` ledger row.
  /// One transaction: a crash cannot leave data without the revoke record, or
  /// the record without the wipe.
  Future<void> wipeConnector(String connector) => _db.transaction(() async {
    await (_db.delete(
      _db.items,
    )..where((t) => t.source.equals(connector))).go();
    await (_db.delete(
      _db.ledger,
    )..where((t) => t.connector.equals(connector))).go();
    await (_db.delete(
      _db.connectorAccounts,
    )..where((t) => t.connector.equals(connector))).go();
    await addLedger(connector, LedgerAction.revoke);
  });

  // ---- mapping -----------------------------------------------------------

  ConnectorItem _toItem(ItemRow r) => ConnectorItem(
    id: r.id,
    source: r.source,
    externalId: r.externalId,
    kind: r.kind,
    title: r.title,
    body: r.body,
    people: _people(r.peopleJson),
    startsAt: r.startsAt,
    sentAt: r.sentAt,
    flags: _map(r.flagsJson),
    summary: r.summary,
    summaryModel: r.summaryModel,
    updatedAt: r.updatedAt,
  );

  /// Public so `SearchIndex` implementations map rows the same way.
  ConnectorItem itemFromRow(ItemRow r) => _toItem(r);

  ConnectorAccount _toAccount(ConnectorAccountRow r) => ConnectorAccount(
    connector: r.connector,
    status: r.status,
    label: r.label,
    config: r.configJson == null ? const {} : _map(r.configJson!),
    lastError: r.lastError,
    connectedAt: r.connectedAt,
    lastSyncAt: r.lastSyncAt,
  );

  LedgerEntry _toEntry(LedgerRow r) => LedgerEntry(
    connector: r.connector,
    action: r.action,
    count: r.count,
    at: r.at,
  );
}

List<Person> _people(String raw) {
  try {
    final v = jsonDecode(raw);
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (Person.fromJson(e) case final p?) p,
    ];
  } on FormatException {
    return const [];
  }
}

Map<String, Object?> _map(String raw) {
  try {
    final v = jsonDecode(raw);
    return v is Map ? Map<String, Object?>.from(v) : const {};
  } on FormatException {
    return const {};
  }
}

/// Groups notification [items] (any order) by `flags.pkg`, newest app first.
List<NotificationGroup> groupNotifications(List<ConnectorItem> items) {
  final byPkg = <String, List<ConnectorItem>>{};
  for (final i in items) {
    final pkg = i.flags['pkg'];
    byPkg.putIfAbsent(pkg is String ? pkg : '', () => []).add(i);
  }
  final groups = [
    for (final e in byPkg.entries)
      () {
        final sorted = [...e.value]
          ..sort(
            (a, b) =>
                (b.sentAt ?? b.updatedAt).compareTo(a.sentAt ?? a.updatedAt),
          );
        final label = sorted.first.flags['app'];
        return NotificationGroup(
          package: e.key,
          appLabel: label is String && label.isNotEmpty ? label : e.key,
          items: sorted,
        );
      }(),
  ];
  groups.sort((a, b) => b.latest.compareTo(a.latest));
  return groups;
}

/// Drift stores DateTimes as whole unix seconds and hands them back as local
/// time, so "did it change?" compares whole seconds, not DateTime equality.
int? _sec(DateTime? d) => d == null ? null : d.millisecondsSinceEpoch ~/ 1000;
