import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ConnectorStore store;
  var clock = DateTime.utc(2026, 11, 1, 8);

  setUp(() {
    clock = DateTime.utc(2026, 11, 1, 8);
    db = AppDatabase(NativeDatabase.memory());
    store = ConnectorStore(db: db, clock: () => clock);
  });
  tearDown(() => db.close());

  ItemDraft event(String id, {String title = 'Standup', DateTime? at}) =>
      ItemDraft(
        externalId: id,
        kind: ItemKind.event,
        title: title,
        startsAt: at ?? DateTime.utc(2026, 11, 1, 9),
        people: const [Person(name: 'Ravi', email: 'ravi@example.com')],
        flags: const {'allDay': false},
      );

  group('upsertItems', () {
    test(
      'inserts, then re-syncing the same data is a no-op (dedupe)',
      () async {
        final first = await store.upsertItems('calendar', [
          event('a'),
          event('b'),
        ]);
        expect((first.inserted, first.updated, first.unchanged), (2, 0, 0));

        final again = await store.upsertItems('calendar', [
          event('a'),
          event('b'),
        ]);
        expect((again.inserted, again.updated, again.unchanged), (0, 0, 2));
        expect(await store.countItems('calendar'), 2);
      },
    );

    test(
      'a changed event updates in place and drops its stale summary',
      () async {
        await store.upsertItems('calendar', [event('a')]);
        final id = (await store.itemsOf('calendar')).single.id;
        await store.setSummary(id, 'A short sync.', 'qwen-0.5b');

        clock = clock.add(const Duration(hours: 1));
        final r = await store.upsertItems('calendar', [
          event('a', title: 'Standup (moved)'),
        ]);
        expect((r.inserted, r.updated), (0, 1));
        final item = (await store.itemsOf('calendar')).single;
        expect(item.id, id);
        expect(item.title, 'Standup (moved)');
        expect(item.summary, isNull);
        expect(item.summaryModel, isNull);
      },
    );

    test('a metadata-only change keeps the summary', () async {
      await store.upsertItems('calendar', [event('a')]);
      final id = (await store.itemsOf('calendar')).single.id;
      await store.setSummary(id, 'Keep me.', 'm');
      await store.upsertItems('calendar', [
        event('a', at: DateTime.utc(2026, 11, 1, 10)),
      ]);
      expect((await store.itemsOf('calendar')).single.summary, 'Keep me.');
    });

    test('the same externalId in two sources are two items', () async {
      await store.upsertItems('calendar', [event('x')]);
      await store.upsertItems('notifications', [
        const ItemDraft(externalId: 'x', kind: ItemKind.notification),
      ]);
      expect(await store.countItems('calendar'), 1);
      expect(await store.countItems('notifications'), 1);
    });

    test('a repeated id inside one batch keeps the last draft', () async {
      await store.upsertItems('calendar', [
        event('a', title: 'one'),
        event('a', title: 'two'),
      ]);
      expect((await store.itemsOf('calendar')).single.title, 'two');
    });

    test('body is capped at 8 KB and never splits a surrogate pair', () async {
      final long = '${'a' * (maxItemBodyChars - 1)}\u{1F600}tail';
      await store.upsertItems('folder', [
        ItemDraft(externalId: 'f', kind: ItemKind.file, body: long),
      ]);
      final body = (await store.itemsOf('folder')).single.body;
      expect(body.length, lessThanOrEqualTo(maxItemBodyChars));
      expect(body.length, maxItemBodyChars - 1);
      expect(body.endsWith('a'), isTrue);
    });

    test('people and flags round-trip', () async {
      await store.upsertItems('calendar', [event('a')]);
      final item = (await store.itemsOf('calendar')).single;
      expect(item.people, const [
        Person(name: 'Ravi', email: 'ravi@example.com'),
      ]);
      expect(item.flags['allDay'], false);
    });
  });

  group('window + prefix + prune', () {
    test(
      'removeMissingInWindow deletes only stale events inside the window',
      () async {
        await store.upsertItems('calendar', [
          event('keep', at: DateTime.utc(2026, 11, 2, 9)),
          event('gone', at: DateTime.utc(2026, 11, 3, 9)),
          event('outside', at: DateTime.utc(2026, 12, 25, 9)),
        ]);
        final n = await store.removeMissingInWindow(
          'calendar',
          ItemKind.event,
          from: DateTime.utc(2026, 10, 31),
          to: DateTime.utc(2026, 11, 15),
          keep: {'keep'},
        );
        expect(n, 1);
        final ids = (await store.itemsOf('calendar')).map((i) => i.externalId);
        expect(ids, unorderedEquals(['keep', 'outside']));
      },
    );

    test(
      'removeByExternalIds is exact: % and _ in ids are not wildcards, other '
      'sources are untouched',
      () async {
        ItemDraft f(String id) =>
            ItemDraft(externalId: id, kind: ItemKind.file);
        await store.upsertItems('folder', [
          f('content://a/doc%2F1_x'),
          f('content://a/doc%2F1_x#2'),
          f('content://a/doc%2F1_xyz'),
          f('content://a/doc%2F1%x#2'),
        ]);
        await store.upsertItems('calendar', [f('content://a/doc%2F1_x')]);
        final n = await store.removeByExternalIds('folder', [
          'content://a/doc%2F1_x',
          'content://a/doc%2F1_x#2',
        ]);
        expect(n, 2);
        expect(await store.countItems('calendar'), 1);
        expect(
          (await store.itemsOf('folder')).map((i) => i.externalId),
          unorderedEquals([
            'content://a/doc%2F1_xyz',
            'content://a/doc%2F1%x#2',
          ]),
        );
      },
    );

    test('pruneOlderThan uses sentAt, falling back to updatedAt', () async {
      await store.upsertItems('notifications', [
        ItemDraft(
          externalId: 'old',
          kind: ItemKind.notification,
          sentAt: DateTime.utc(2026, 10, 1),
        ),
        ItemDraft(
          externalId: 'new',
          kind: ItemKind.notification,
          sentAt: DateTime.utc(2026, 10, 31),
        ),
      ]);
      await store.pruneOlderThan('notifications', DateTime.utc(2026, 10, 25));
      expect((await store.itemsOf('notifications')).single.externalId, 'new');
    });
  });

  group('queries', () {
    test('today vs next events', () async {
      await store.upsertItems('calendar', [
        event('yesterday', at: DateTime(2026, 10, 31, 20)),
        event('t1', at: DateTime(2026, 11, 1, 9)),
        event('t2', at: DateTime(2026, 11, 1, 15)),
        event('tomorrow', at: DateTime(2026, 11, 2, 9)),
      ]);
      final today = await store
          .watchTodaysEvents(DateTime(2026, 11, 1, 8))
          .first;
      expect(today.map((e) => e.externalId), ['t1', 't2']);
      final next = await store
          .watchNextEvents(DateTime(2026, 11, 1, 10), limit: 2)
          .first;
      expect(next.map((e) => e.externalId), ['t2', 'tomorrow']);
    });

    test('notifications group by app, newest app first', () async {
      ItemDraft n(String id, String pkg, String app, int minute) => ItemDraft(
        externalId: id,
        kind: ItemKind.notification,
        title: id,
        sentAt: DateTime.utc(2026, 11, 1, 8, minute),
        flags: {'pkg': pkg, 'app': app},
      );
      await store.upsertItems('notifications', [
        n('a1', 'com.a', 'Alpha', 1),
        n('b1', 'com.b', 'Beta', 5),
        n('a2', 'com.a', 'Alpha', 9),
      ]);
      final groups = await store.watchNotificationsByApp().first;
      expect(groups.map((g) => g.appLabel), ['Alpha', 'Beta']);
      expect(groups.first.items.map((i) => i.externalId), ['a2', 'a1']);
    });

    test('contactForEmail is case-insensitive', () async {
      await store.upsertItems('contacts', [
        const ItemDraft(
          externalId: 'c1',
          kind: ItemKind.contact,
          title: 'Ravi Kumar',
          people: [Person(name: 'Ravi Kumar', email: 'Ravi@Example.com')],
        ),
      ]);
      expect(
        (await store.contactForEmail('ravi@example.com'))?.title,
        'Ravi Kumar',
      );
      expect(await store.contactForEmail('nobody@example.com'), isNull);
    });
  });

  group('accounts, ledger, revoke', () {
    test('saveAccount creates then patches only the given fields', () async {
      await store.saveAccount(
        'calendar',
        status: 'connected',
        config: {'x': 1},
      );
      await store.saveAccount('calendar', lastSyncAt: clock);
      final a = (await store.account('calendar'))!;
      expect(a.status, 'connected');
      expect(a.config, {'x': 1});
      expect(a.lastSyncAt!.isAtSameMomentAs(clock), isTrue);
      await store.saveAccount('calendar', lastError: 'boom');
      expect((await store.account('calendar'))!.lastError, 'boom');
      await store.saveAccount('calendar', clearError: true);
      expect((await store.account('calendar'))!.lastError, isNull);
    });

    test('wipeConnector deletes content + content ledger, keeps a revoke row, '
        'leaves other connectors alone', () async {
      await store.saveAccount('calendar');
      await store.upsertItems('calendar', [event('a'), event('b')]);
      await store.addLedger('calendar', LedgerAction.read, count: 2);
      await store.saveAccount('folder');
      await store.upsertItems('folder', [
        const ItemDraft(externalId: 'f', kind: ItemKind.file),
      ]);
      await store.addLedger('folder', LedgerAction.read, count: 1);

      clock = clock.add(const Duration(minutes: 5));
      await store.wipeConnector('calendar');

      expect(await store.countItems('calendar'), 0);
      expect(await store.account('calendar'), isNull);
      final cal = await store.ledger(connector: 'calendar');
      expect(cal.map((e) => e.action), [LedgerAction.revoke]);
      expect(await store.countItems('folder'), 1);
      expect(await store.account('folder'), isNotNull);
      expect(await store.ledger(connector: 'folder'), hasLength(1));
    });

    test('ledger is newest first', () async {
      await store.addLedger('calendar', LedgerAction.read, count: 1);
      clock = clock.add(const Duration(minutes: 1));
      await store.addLedger('calendar', LedgerAction.read, count: 2);
      expect((await store.ledger()).map((e) => e.count), [2, 1]);
    });
  });
}
