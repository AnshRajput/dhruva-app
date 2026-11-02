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

/// One indexed file of the connected folder, as the Library shows it.
final class FolderFile {
  final int itemId;
  final String fileId;
  final String name;
  final DateTime? modified;
  final int? pages;

  /// Why the file could not be read for search (`tooLarge`, `scanned`,
  /// `unreadable`, ...), or null when it is searchable.
  final String? problem;
  const FolderFile({
    required this.itemId,
    required this.fileId,
    required this.name,
    required this.modified,
    required this.pages,
    required this.problem,
  });

  bool get ready => problem == null;
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
  ///
  /// [requireAccount] (every sync path sets it) makes the write a no-op once
  /// the opt-in row is gone, checked inside the same transaction as the write:
  /// a sync still running when the user revokes (in this isolate or the
  /// background one) can never bring revoked content back.
  Future<IngestResult> upsertItems(
    String source,
    List<ItemDraft> drafts, {
    bool requireAccount = false,
  }) async {
    if (drafts.isEmpty) return const IngestResult();
    // Last draft wins if a connector repeats an id within one batch.
    final byId = <String, ItemDraft>{for (final d in drafts) d.externalId: d};
    var inserted = 0, updated = 0, unchanged = 0;
    await _db.transaction(() async {
      if (requireAccount && await account(source) == null) return;
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
        final old = existing[d.externalId];
        // "Marked read" is the user's own state: a re-ingest of the same
        // item (an updated notification) must not bring it back as unread.
        final keepRead = old != null && _map(old.flagsJson)['read'] == true;
        final flags = jsonEncode(
          keepRead ? {...d.flags, 'read': true} : d.flags,
        );
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

  /// Deletes [source] items with exactly these external ids (a file's section
  /// rows, for instance). Exact match in chunks: ids such as SAF uris contain
  /// `%` and `_`, which must never be treated as wildcards.
  /// Runs [body] as one transaction: all of its writes land, or none do.
  Future<T> inTransaction<T>(Future<T> Function() body) =>
      _db.transaction(body);

  Future<int> removeByExternalIds(
    String source,
    Iterable<String> externalIds,
  ) async {
    final ids = externalIds.toSet().toList();
    var n = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
      n +=
          await (_db.delete(_db.items)
                ..where((t) => t.source.equals(source))
                ..where((t) => t.externalId.isIn(chunk)))
              .go();
    }
    return n;
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

  /// (externalId, flags) of one source's items of [kind], without the bodies:
  /// the folder re-index only needs fileId/mtime/size, not up to 96 MB of text.
  Future<List<({String externalId, Map<String, Object?> flags})>> flagsOf(
    String source,
    ItemKind kind,
  ) async {
    final t = _db.items;
    final q = _db.selectOnly(t)
      ..addColumns([t.externalId, t.flagsJson])
      ..where(t.source.equals(source) & t.kind.equalsValue(kind));
    return [
      for (final r in await q.get())
        (
          externalId: r.read(t.externalId)!,
          flags: _map(r.read(t.flagsJson) ?? '{}'),
        ),
    ];
  }

  Future<List<ConnectorItem>> itemsByIds(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];
    final rows = await (_db.select(
      _db.items,
    )..where((t) => t.id.isIn(list))).get();
    return [for (final r in rows) _toItem(r)];
  }

  /// Events starting in [from, to), earliest first (Ask reads these directly
  /// for calendar questions instead of waiting for a keyword hit).
  Future<List<ConnectorItem>> eventsBetween(
    DateTime from,
    DateTime to, {
    int limit = 8,
  }) async {
    final q = _db.select(_db.items)
      ..where((t) => t.kind.equalsValue(ItemKind.event))
      ..where(
        (t) =>
            t.startsAt.isBiggerOrEqualValue(from) &
            t.startsAt.isSmallerThanValue(to),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startsAt)])
      ..limit(limit);
    return [for (final r in await q.get()) _toItem(r)];
  }

  /// Display names of the stored contact items (people met in events/mail).
  /// Ask uses them to notice "what did Ravi say" without a model call.
  Future<List<String>> contactNames() async {
    final q = _db.selectOnly(_db.items)
      ..addColumns([_db.items.title])
      ..where(_db.items.kind.equalsValue(ItemKind.contact));
    return [
      for (final r in await q.get())
        if ((r.read(_db.items.title) ?? '').trim().isNotEmpty)
          r.read(_db.items.title)!.trim(),
    ];
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

  /// Sets (or, with a null [value], removes) one key in an item's flags, such
  /// as the user's "read" mark, leaving the rest alone. No-op if the item is
  /// gone.
  Future<void> setItemFlag(int itemId, String key, Object? value) =>
      _db.transaction(() async {
        final row = await (_db.select(
          _db.items,
        )..where((t) => t.id.equals(itemId))).getSingleOrNull();
        if (row == null) return;
        final flags = Map<String, Object?>.from(_map(row.flagsJson));
        if (value == null) {
          flags.remove(key);
        } else {
          flags[key] = value;
        }
        await (_db.update(_db.items)..where((t) => t.id.equals(itemId))).write(
          ItemsCompanion(flagsJson: Value(jsonEncode(flags))),
        );
      });

  /// All sections of one folder file (they share the file id), in order.
  Future<List<ConnectorItem>> fileSections(String fileId) async {
    // Section rows are `<fileId>` then `<fileId>#2`...: fetch by prefix, then
    // keep only exact matches (a prefix can also match a longer file id).
    final rows =
        await (_db.select(_db.items)
              ..where((t) => t.source.equals(ConnectorIds.folder))
              ..where((t) => t.kind.equalsValue(ItemKind.file))
              ..where((t) => t.externalId.like('$fileId%'))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return [
      for (final r in rows)
        if (r.externalId == fileId || r.externalId.startsWith('$fileId#'))
          _toItem(r),
    ];
  }

  /// One entry per indexed folder file (its first section), newest change
  /// first, without reading any body. Live: drives the Library folder block.
  Stream<List<FolderFile>> watchFolderFiles() {
    final t = _db.items;
    final q = _db.selectOnly(t)
      ..addColumns([t.id, t.externalId, t.title, t.sentAt, t.flagsJson])
      ..where(
        t.source.equals(ConnectorIds.folder) &
            t.kind.equalsValue(ItemKind.file),
      );
    return q.watch().map((rows) {
      final byFile = <String, FolderFile>{};
      for (final r in rows) {
        final flags = _map(r.read(t.flagsJson) ?? '{}');
        final externalId = r.read(t.externalId)!;
        final fileId = (flags['fileId'] as String?) ?? externalId;
        if (externalId != fileId) continue; // a later section of the same file
        byFile[fileId] = FolderFile(
          itemId: r.read(t.id)!,
          fileId: fileId,
          name: r.read(t.title) ?? '',
          modified: r.read(t.sentAt),
          pages: flags['pages'] as int?,
          problem: flags['unreadable'] as String?,
        );
      }
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      return byFile.values.toList()
        ..sort((a, b) => (b.modified ?? epoch).compareTo(a.modified ?? epoch));
    });
  }

  /// Notifications newer than [since], newest first, one row each (the Inbox).
  Stream<List<ConnectorItem>> watchNotifications({DateTime? since}) {
    final q = _db.select(_db.items)
      ..where((t) => t.kind.equalsValue(ItemKind.notification))
      ..orderBy([
        (t) => OrderingTerm.desc(t.sentAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    if (since != null) q.where((t) => t.sentAt.isBiggerOrEqualValue(since));
    return q.watch().map((rows) => [for (final r in rows) _toItem(r)]);
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

  /// The next [limit] events that are happening now or still ahead, earliest
  /// start first: a timed event counts from its start until its end, so a
  /// meeting in progress (and one overlapping it) shows; an all-day event only
  /// counts while it is still ahead, never one from an earlier day. The end
  /// lives in `flags` (no column), so this reads from two days back and
  /// filters in Dart.
  Stream<List<ConnectorItem>> watchNextEvents(DateTime now, {int limit = 2}) {
    return _events(
      (t) => t.startsAt.isBiggerOrEqualValue(
        now.subtract(const Duration(days: 2)),
      ),
    ).map(
      (events) => [
        for (final e in events)
          if (_isNowOrAhead(e, now)) e,
      ].take(limit).toList(),
    );
  }

  static bool _isNowOrAhead(ConnectorItem e, DateTime now) {
    final start = e.startsAt;
    if (start == null) return false;
    if (!start.isBefore(now)) return true;
    if (e.flags['allDay'] == true) return false;
    final end = e.flags['end'];
    return end is int && DateTime.fromMillisecondsSinceEpoch(end).isAfter(now);
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

  /// "Clear ledger": forgets the reading history (counts only, never content).
  Future<void> clearLedger() => _db.delete(_db.ledger).go();

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
  /// [onlyIfExists] never creates the row (a sync must not resurrect an opt-in
  /// the user has revoked).
  Future<void> saveAccount(
    String connector, {
    String? status,
    String? label,
    Map<String, Object?>? config,
    String? lastError,
    bool clearError = false,
    DateTime? lastSyncAt,
    bool onlyIfExists = false,
  }) => _db.transaction(() async {
    final existing = await account(connector);
    if (existing == null) {
      if (onlyIfExists) return;
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
  });

  /// End of a successful sync: the content ledger row and the account's
  /// lastSyncAt in one transaction, skipped entirely if the connector was
  /// revoked meanwhile.
  Future<void> recordSync(
    String connector, {
    required int count,
    bool ledger = true,
  }) => _db.transaction(() async {
    if (await account(connector) == null) return;
    if (ledger) await addLedger(connector, LedgerAction.read, count: count);
    await saveAccount(
      connector,
      status: 'connected',
      clearError: true,
      lastSyncAt: now,
      onlyIfExists: true,
    );
  });

  /// A failed sync, same revoke guard as [recordSync].
  Future<void> recordFailure(String connector, String message) =>
      _db.transaction(() async {
        if (await account(connector) == null) return;
        await saveAccount(
          connector,
          status: 'needsAttention',
          lastError: message,
          onlyIfExists: true,
        );
        await addLedger(connector, LedgerAction.failed);
      });

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
    // Library items that quote this connector's data go with it (the rule is
    // documented on `encodeConnectors` in library_store.dart).
    final like = Variable<String>('%,$connector,%');
    await _db.customUpdate(
      'DELETE FROM saved_answers WHERE source_connectors LIKE ?',
      variables: [like],
      updates: {_db.savedAnswers},
    );
    await _db.customUpdate(
      'DELETE FROM todos WHERE source_connectors LIKE ?',
      variables: [like],
      updates: {_db.todos},
    );
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
    return [for (final e in v) ?Person.fromJson(e)];
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
