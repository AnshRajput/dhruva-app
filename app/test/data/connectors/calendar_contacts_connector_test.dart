import 'package:dhruva/data/connectors/calendar_connector.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_connector_sources.dart';

void main() {
  late AppDatabase db;
  late ConnectorTestKit kit;
  var now = DateTime.utc(2026, 11, 1, 8);

  setUp(() {
    now = DateTime.utc(2026, 11, 1, 8);
    db = AppDatabase(NativeDatabase.memory());
    kit = ConnectorTestKit.create(db, clock: () => now);
  });
  tearDown(() async {
    await kit.dispose();
    await db.close();
  });

  group('calendar permission states', () {
    test('starts not connected', () async {
      await kit.hub.calendar.refreshStatus();
      expect(kit.hub.calendar.currentStatus.state, ConnectorState.notConnected);
    });

    test(
      'connect: prompt granted -> connected, one connect ledger row',
      () async {
        await kit.hub.calendar.connect();
        expect(kit.calendar.requests, 1);
        expect(kit.hub.calendar.currentStatus.state, ConnectorState.connected);
        final ledger = await kit.hub.store.ledger(connector: 'calendar');
        expect(ledger.map((e) => e.action), [LedgerAction.connect]);
      },
    );

    test(
      'connect: denied -> permissionDenied naming the fix, nothing stored',
      () async {
        kit.calendar.afterRequest = DevicePermission.denied;
        await kit.hub.calendar.connect();
        final s = kit.hub.calendar.currentStatus;
        expect(s.state, ConnectorState.permissionDenied);
        expect(s.detail, contains('Open settings'));
        expect(await kit.hub.store.account('calendar'), isNull);
        expect(await kit.hub.store.ledger(connector: 'calendar'), isEmpty);
      },
    );

    test(
      'a grant revoked in system settings shows as permissionDenied',
      () async {
        await kit.hub.calendar.connect();
        kit.calendar.perm = DevicePermission.denied;
        await kit.hub.calendar.refreshStatus();
        expect(
          kit.hub.calendar.currentStatus.state,
          ConnectorState.permissionDenied,
        );
        await expectLater(
          kit.hub.calendar.sync(),
          throwsA(
            isA<ConnectorException>().having(
              (e) => e.state,
              'state',
              ConnectorState.permissionDenied,
            ),
          ),
        );
        // ...and the user can jump to the OS page.
        await kit.hub.calendar.openSystemSettings();
        expect(kit.calendar.settingsOpened, 1);
      },
    );

    test('sync without connecting is refused', () async {
      await expectLater(
        kit.hub.calendar.sync(),
        throwsA(isA<ConnectorException>()),
      );
    });
  });

  group('calendar ingestion', () {
    test(
      'reads next 14 days + last day, stores events, writes a ledger row',
      () async {
        await kit.hub.calendar.connect();
        kit.calendar.items = [
          calEvent(
            'a',
            start: DateTime.utc(2026, 11, 1, 9),
            attendees: const [Person(name: 'Ravi', email: 'ravi@example.com')],
            location: 'Room 4',
            description: 'Quarterly numbers',
          ),
        ];
        final r = await kit.hub.calendar.sync();
        expect(r.read, 1);
        expect(
          kit.calendar.lastFrom,
          now.subtract(const Duration(days: calendarDaysBack)),
        );
        expect(
          kit.calendar.lastTo,
          now.add(const Duration(days: calendarDaysAhead)),
        );
        final item = (await kit.hub.store.itemsOf('calendar')).single;
        expect(item.title, 'Standup');
        expect(item.body, 'Location: Room 4\nQuarterly numbers');
        expect(item.people.single.email, 'ravi@example.com');
        final ledger = await kit.hub.store.ledger(connector: 'calendar');
        expect(ledger.first.action, LedgerAction.read);
        expect(ledger.first.count, 1);
        expect(kit.hub.calendar.currentStatus.lastSyncAt, isNotNull);
      },
    );

    test('re-sync dedupes; a moved event updates in place', () async {
      await kit.hub.calendar.connect();
      kit.calendar.items = [calEvent('a', start: DateTime.utc(2026, 11, 1, 9))];
      await kit.hub.calendar.sync();
      final second = await kit.hub.calendar.sync();
      expect(second.changed, 0);
      expect(await kit.hub.store.countItems('calendar'), 1);

      kit.calendar.items = [
        calEvent(
          'a',
          title: 'Standup (moved)',
          start: DateTime.utc(2026, 11, 1, 10),
        ),
      ];
      final third = await kit.hub.calendar.sync();
      expect(third.changed, 1);
      expect(
        (await kit.hub.store.itemsOf('calendar')).single.title,
        'Standup (moved)',
      );
    });

    test('an event deleted on the phone leaves the store', () async {
      await kit.hub.calendar.connect();
      kit.calendar.items = [
        calEvent('keep', start: DateTime.utc(2026, 11, 2, 9)),
        calEvent('gone', start: DateTime.utc(2026, 11, 3, 9)),
      ];
      await kit.hub.calendar.sync();
      kit.calendar.items = [
        calEvent('keep', start: DateTime.utc(2026, 11, 2, 9)),
      ];
      await kit.hub.calendar.sync();
      expect(
        (await kit.hub.store.itemsOf('calendar')).map((i) => i.externalId),
        ['keep'],
      );
    });

    test(
      'a failed read keeps the data, says what to do, and logs a failure',
      () async {
        await kit.hub.calendar.connect();
        kit.calendar.items = [
          calEvent('a', start: DateTime.utc(2026, 11, 1, 9)),
        ];
        await kit.hub.calendar.sync();

        kit.calendar.failRead = true;
        await expectLater(
          kit.hub.calendar.sync(),
          throwsA(isA<ConnectorException>()),
        );
        expect(await kit.hub.store.countItems('calendar'), 1);
        final s = kit.hub.calendar.currentStatus;
        expect(s.state, ConnectorState.needsAttention);
        expect(s.detail, contains('try again'));
        final actions = (await kit.hub.store.ledger(
          connector: 'calendar',
        )).map((e) => e.action);
        expect(actions, contains(LedgerAction.failed));

        // Recovery clears the card.
        kit.calendar.failRead = false;
        await kit.hub.calendar.sync();
        expect(kit.hub.calendar.currentStatus.state, ConnectorState.connected);
      },
    );

    test('calendars the user switched off are not stored', () async {
      await kit.hub.calendar.connect();
      await kit.hub.calendar.setExcludedCalendars(['work']);
      kit.calendar.items = [
        calEvent('p', start: DateTime.utc(2026, 11, 2, 9), calendarId: 'home'),
        calEvent('w', start: DateTime.utc(2026, 11, 2, 10), calendarId: 'work'),
      ];
      await kit.hub.calendar.sync();
      expect(
        (await kit.hub.store.itemsOf('calendar')).map((i) => i.externalId),
        ['p'],
      );
    });

    test('an untitled event gets a readable title', () async {
      await kit.hub.calendar.connect();
      kit.calendar.items = [
        calEvent('a', title: '  ', start: DateTime.utc(2026, 11, 1, 9)),
      ];
      await kit.hub.calendar.sync();
      expect(
        (await kit.hub.store.itemsOf('calendar')).single.title,
        '(No title)',
      );
    });
  });

  group('revoke', () {
    test('tells the app so derived copies (the brief cache) can go', () async {
      var wiped = 0;
      kit.hub.onWiped = () async => wiped++;
      await kit.hub.calendar.connect();
      await kit.hub.calendar.revoke();
      expect(wiped, 1);
      // A hook that throws must not block the revoke.
      kit.hub.onWiped = () async => throw StateError('disk full');
      await kit.hub.calendar.connect();
      await kit.hub.calendar.revoke();
      expect(kit.hub.calendar.currentStatus.state, ConnectorState.notConnected);
    });

    test('wipes events + content ledger, keeps a revoke row, back to not '
        'connected', () async {
      await kit.hub.calendar.connect();
      kit.calendar.items = [calEvent('a', start: DateTime.utc(2026, 11, 1, 9))];
      await kit.hub.calendar.sync();
      await kit.hub.calendar.revoke();
      expect(await kit.hub.store.countItems('calendar'), 0);
      expect(await kit.hub.store.account('calendar'), isNull);
      expect(
        (await kit.hub.store.ledger(
          connector: 'calendar',
        )).map((e) => e.action),
        [LedgerAction.revoke],
      );
      expect(kit.hub.calendar.currentStatus.state, ConnectorState.notConnected);
    });
  });

  group('contacts', () {
    Future<void> seedEvent() async {
      await kit.hub.calendar.connect();
      kit.calendar.items = [
        calEvent(
          'a',
          start: DateTime.utc(2026, 11, 1, 9),
          attendees: const [
            Person(name: 'R', email: 'Ravi@Example.com'),
            Person(name: 'S', email: 'sara@example.com'),
            Person(name: 'No email'),
          ],
        ),
      ];
      await kit.hub.calendar.sync();
    }

    test(
      'resolves ONLY people from synced items, by email, nothing else',
      () async {
        await seedEvent();
        kit.contacts.byAddress.addAll({
          'ravi@example.com': const DeviceContact(
            id: 'c1',
            name: 'Ravi Kumar',
            thumbnail: [1, 2, 3],
          ),
          // Someone in the address book who is in no event: must never be read.
          'stranger@example.com': const DeviceContact(
            id: 'c9',
            name: 'Stranger',
          ),
        });
        await kit.hub.contacts.connect();
        final r = await kit.hub.contacts.sync();
        expect(r.read, 1);
        expect(
          kit.contacts.lookups,
          unorderedEquals(['ravi@example.com', 'sara@example.com']),
        );
        final item = (await kit.hub.store.itemsOf('contacts')).single;
        expect(item.title, 'Ravi Kumar');
        expect(item.people.single.email, 'ravi@example.com');
        expect(item.flags['photo'], isA<String>());
        expect(
          (await kit.hub.store.contactForEmail('RAVI@example.com'))?.title,
          'Ravi Kumar',
        );
      },
    );

    test('an oversized avatar is dropped, not stored', () async {
      await seedEvent();
      kit.contacts.byAddress['ravi@example.com'] = DeviceContact(
        id: 'c1',
        name: 'Ravi',
        thumbnail: List.filled(60 * 1024, 1),
      );
      await kit.hub.contacts.connect();
      await kit.hub.contacts.sync();
      expect(
        (await kit.hub.store.itemsOf('contacts')).single.flags,
        isNot(contains('photo')),
      );
    });

    test('two addresses of one contact make one item with both', () async {
      await seedEvent();
      final c = const DeviceContact(id: 'c1', name: 'Ravi Kumar');
      kit.contacts.byAddress['ravi@example.com'] = c;
      kit.contacts.byAddress['sara@example.com'] = c;
      await kit.hub.contacts.connect();
      await kit.hub.contacts.sync();
      final item = (await kit.hub.store.itemsOf('contacts')).single;
      expect(
        item.people.map((p) => p.email),
        unorderedEquals(['ravi@example.com', 'sara@example.com']),
      );
    });

    test(
      'permission denied -> status says Open settings; sync refused',
      () async {
        kit.contacts.afterRequest = DevicePermission.denied;
        await kit.hub.contacts.connect();
        expect(
          kit.hub.contacts.currentStatus.state,
          ConnectorState.permissionDenied,
        );
        expect(
          kit.hub.contacts.currentStatus.detail,
          contains('Open settings'),
        );
        await kit.hub.contacts.openSystemSettings();
        expect(kit.contacts.settingsOpened, 1);
      },
    );

    test('a contacts failure is a needs-attention card, not a crash', () async {
      await seedEvent();
      await kit.hub.contacts.connect();
      kit.contacts.failRead = true;
      await expectLater(
        kit.hub.contacts.sync(),
        throwsA(isA<ConnectorException>()),
      );
      expect(
        kit.hub.contacts.currentStatus.state,
        ConnectorState.needsAttention,
      );
    });

    test('revoke deletes contact items', () async {
      await seedEvent();
      kit.contacts.byAddress['ravi@example.com'] = const DeviceContact(
        id: 'c1',
        name: 'Ravi',
      );
      await kit.hub.contacts.connect();
      await kit.hub.contacts.sync();
      await kit.hub.contacts.revoke();
      expect(await kit.hub.store.countItems('contacts'), 0);
    });
  });
}
