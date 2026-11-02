import 'dart:async';

import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/router/inbox_availability.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_hub.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_connector_sources.dart';

void main() {
  late AppDatabase db;
  late ConnectorTestKit kit;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    kit = ConnectorTestKit.create(db, clock: () => DateTime.now());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectorHubProvider.overrideWith((ref) async => kit.hub),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await kit.dispose();
    await db.close();
  });

  /// First data value of a stream provider. Listening (not `read(.future)`)
  /// keeps the provider alive; Riverpod 3 pauses unlistened providers.
  Future<T> firstValue<T>(StreamProvider<T> provider) async {
    final c = Completer<T>();
    final sub = container.listen<AsyncValue<T>>(provider, (_, next) {
      final v = next.value;
      if (v != null && !c.isCompleted) c.complete(v);
    }, fireImmediately: true);
    final v = await c.future.timeout(const Duration(seconds: 5));
    sub.close();
    return v;
  }

  Future<List<ConnectorEntry>> nextList() async {
    // Wait until the list provider has produced at least one value.
    final c = Completer<List<ConnectorEntry>>();
    final sub = container.listen(connectorListProvider, (_, next) {
      final v = next.value;
      if (v != null && !c.isCompleted) c.complete(v);
    }, fireImmediately: true);
    final v = await c.future.timeout(const Duration(seconds: 5));
    sub.close();
    return v;
  }

  test(
    'connector list shows the supported connectors with their status',
    () async {
      final list = await nextList();
      // Display order: Calendar, Contacts, Notes folder, Notifications.
      expect(list.map((e) => e.connector.id), [
        'calendar',
        'contacts',
        'folder',
        'notifications',
      ]);
      expect(
        list.every((e) => e.status.state == ConnectorState.notConnected),
        isTrue,
      );
    },
  );

  test('iOS: the notifications connector is not in the list', () async {
    final ios = ConnectorTestKit.create(db, notificationsSupported: false);
    addTearDown(ios.dispose);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectorHubProvider.overrideWith((ref) async => ios.hub),
      ],
    );
    addTearDown(c.dispose);
    final done = Completer<List<ConnectorEntry>>();
    c.listen(connectorListProvider, (_, next) {
      final v = next.value;
      if (v != null && !done.isCompleted) done.complete(v);
    }, fireImmediately: true);
    final list = await done.future.timeout(const Duration(seconds: 5));
    expect(list.map((e) => e.connector.id), isNot(contains('notifications')));
  });

  test('inboxAvailableProvider: false until notifications are connected, '
      'true after, false again after revoke', () async {
    final seen = <bool>[];
    container.listen(
      inboxAvailableProvider,
      (_, v) => seen.add(v),
      fireImmediately: true,
    );
    await nextList();
    expect(container.read(inboxAvailableProvider), isFalse);

    kit.notifications.granted = true;
    await kit.hub.notifications.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(inboxAvailableProvider), isTrue);

    await kit.hub.notifications.revoke();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(inboxAvailableProvider), isFalse);
    expect(seen, containsAllInOrder([false, true, false]));
  });

  test('calendar alone does not make the Inbox available', () async {
    await nextList();
    await kit.hub.calendar.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(inboxAvailableProvider), isFalse);
  });

  test(
    'inbox stays hidden (not an error) while the hub is still loading',
    () async {
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          connectorHubProvider.overrideWith(
            (ref) => Completer<ConnectorHub>().future,
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(inboxAvailableProvider), isFalse);
    },
  );

  test('query providers: today, next, notification groups, ledger', () async {
    final now = DateTime.now();
    final noon = DateTime(now.year, now.month, now.day, 12);
    final tomorrow = noon.add(const Duration(days: 1));
    kit.calendar.items = [
      calEvent(
        't',
        start: noon.isAfter(now) ? noon : now.add(const Duration(minutes: 1)),
      ),
      calEvent('n', start: tomorrow),
    ];
    await kit.hub.calendar.connect();
    await kit.hub.calendar.sync();
    final store = container.read(connectorStoreProvider);
    await store.upsertItems('notifications', [
      ItemDraft(
        externalId: 'x',
        kind: ItemKind.notification,
        title: 'Hi',
        sentAt: now,
        flags: const {'pkg': 'com.a.b', 'app': 'Alpha'},
      ),
    ]);

    final next = await firstValue(nextEventsProvider);
    expect(next.map((e) => e.externalId).toList().length, 2);
    final today = await firstValue(todaysEventsProvider);
    expect(today.map((e) => e.externalId), contains('t'));
    final groups = await firstValue(notificationGroupsProvider);
    expect(groups.single.appLabel, 'Alpha');
    final ledger = await firstValue(ledgerProvider);
    expect(ledger.map((e) => e.action), containsAll(['connect', 'read']));
  });

  test('search provider caches equal queries and filters by source', () async {
    final store = container.read(connectorStoreProvider);
    final index = await container.read(searchIndexProvider.future);
    expect(index.engine, 'fts5');
    await store.upsertItems('folder', [
      const ItemDraft(
        externalId: 'f',
        kind: ItemKind.file,
        title: 'plan.md',
        body: 'budget plan',
      ),
    ]);
    await store.upsertItems('calendar', [
      ItemDraft(
        externalId: 'e',
        kind: ItemKind.event,
        title: 'Budget sync',
        startsAt: DateTime.now(),
      ),
    ]);
    final all = await container.read(
      connectorSearchProvider(ConnectorSearchQuery('budget')).future,
    );
    expect(all, hasLength(2));
    final onlyFiles = await container.read(
      connectorSearchProvider(
        ConnectorSearchQuery('budget', sources: {'folder'}),
      ).future,
    );
    expect(onlyFiles.single.item.externalId, 'f');
    expect(
      ConnectorSearchQuery('a', sources: {'x', 'y'}),
      ConnectorSearchQuery('a', sources: {'y', 'x'}),
    );
    expect(
      ConnectorSearchQuery('a', sources: {'x'}) ==
          ConnectorSearchQuery('a', sources: {'z'}),
      isFalse,
    );
    expect(
      ConnectorSearchQuery('a', sources: {'x', 'y'}).hashCode,
      ConnectorSearchQuery('a', sources: {'y', 'x'}).hashCode,
    );
  });

  test('bootstrap: picks the engine and syncs what is connected', () async {
    kit.calendar.items = [
      calEvent('a', start: DateTime.now().add(const Duration(hours: 1))),
    ];
    kit.calendar.perm = DevicePermission.granted;
    await kit.hub.calendar.connect();
    await container.read(connectorBootstrapProvider.future);
    expect(await kit.hub.store.countItems('calendar'), 1);
  });

  group('background sync scheduling', () {
    late FakeScheduler sched;
    late ConnectorTestKit k;
    setUp(() {
      sched = FakeScheduler();
      k = ConnectorTestKit.create(db, scheduler: sched);
      k.notifications.granted = true;
    });
    tearDown(() => k.dispose());

    test('connecting after launch schedules once; a second connector does '
        'not duplicate', () async {
      await k.hub.syncBackgroundJob(); // launch with nothing connected
      expect(sched.scheduled, 0);
      await k.hub.calendar.connect();
      expect(sched.scheduled, 1);
      await k.hub.notifications.connect();
      expect(sched.scheduled, 1);
    });

    test(
      'revoking one of two keeps the job; revoking the last cancels it',
      () async {
        await k.hub.calendar.connect();
        await k.hub.notifications.connect();
        await k.hub.calendar.revoke();
        expect(sched.cancelled, 0);
        await k.hub.notifications.revoke();
        expect(sched.cancelled, 1);
        // Connecting again re-registers.
        await k.hub.calendar.connect();
        expect(sched.scheduled, 2);
      },
    );

    test('a denied connect schedules nothing', () async {
      k.calendar.afterRequest = DevicePermission.denied;
      await k.hub.calendar.connect();
      expect(sched.scheduled, 0);
    });

    test('app restart with a connected connector still schedules', () async {
      await k.hub.calendar.connect();
      final restarted = ConnectorTestKit.create(db, scheduler: sched);
      addTearDown(restarted.dispose);
      restarted.calendar.perm = DevicePermission.granted;
      await restarted.hub.calendar.refreshStatus();
      await restarted.hub.syncBackgroundJob();
      expect(sched.scheduled, 2); // once per process; the job itself dedupes
    });
  });
}
