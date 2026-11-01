import 'package:dhruva/data/connectors/background_sync.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/connectors/sync_service.dart';
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
    kit.calendar.items = [
      calEvent(
        'a',
        start: DateTime.utc(2026, 11, 1, 9),
        attendees: const [Person(name: 'Ravi', email: 'ravi@example.com')],
      ),
    ];
    kit.contacts.byAddress['ravi@example.com'] = const DeviceContact(
      id: 'c1',
      name: 'Ravi Kumar',
    );
  });
  tearDown(() async {
    await kit.dispose();
    await db.close();
  });

  test('syncs only connected sources, in order (contacts after the people '
      'they resolve exist)', () async {
    await kit.hub.calendar.connect();
    await kit.hub.contacts.connect();
    final report = await kit.hub.sync.refresh();
    expect(report.outcomes.keys, ['calendar', 'contacts']);
    expect(report.allOk, isTrue);
    expect(report.totalRead, 2);
    // The contact was resolved from the event synced a moment earlier.
    expect(
      (await kit.hub.store.itemsOf('contacts')).single.title,
      'Ravi Kumar',
    );
  });

  test('every sync writes a ledger row per connector', () async {
    await kit.hub.calendar.connect();
    await kit.hub.sync.refresh();
    await kit.hub.sync.refresh();
    final reads = (await kit.hub.store.ledger(
      connector: 'calendar',
    )).where((e) => e.action == LedgerAction.read);
    expect(reads, hasLength(2));
  });

  test('one failing source does not stop the others', () async {
    await kit.hub.calendar.connect();
    await kit.hub.contacts.connect();
    kit.calendar.failRead = true;
    final report = await kit.hub.sync.refresh();
    expect(report.outcomes['calendar']!.ok, isFalse);
    expect(report.outcomes['calendar']!.error!.message, contains('calendar'));
    expect(report.outcomes['contacts']!.ok, isTrue);
    expect(report.allOk, isFalse);
  });

  test('a source that needs attention is retried and recovers', () async {
    await kit.hub.calendar.connect();
    kit.calendar.failRead = true;
    await kit.hub.sync.refresh();
    expect(kit.hub.calendar.currentStatus.state, ConnectorState.needsAttention);
    kit.calendar.failRead = false;
    final report = await kit.hub.sync.refresh();
    expect(report.outcomes['calendar']!.ok, isTrue);
    expect(kit.hub.calendar.currentStatus.state, ConnectorState.connected);
  });

  test('a source whose OS permission was switched off is skipped (not '
      'retried in a loop)', () async {
    await kit.hub.calendar.connect();
    kit.calendar.perm = DevicePermission.denied;
    final report = await kit.hub.sync.refresh();
    expect(report.outcomes, isEmpty);
    expect(
      kit.hub.calendar.currentStatus.state,
      ConnectorState.permissionDenied,
    );
  });

  test('nothing connected: nothing runs', () async {
    final report = await kit.hub.sync.refresh();
    expect(report.outcomes, isEmpty);
    expect(report.allOk, isTrue);
  });

  test('app-open sync skips sources synced in the last 10 minutes; manual '
      'refresh does not', () async {
    await kit.hub.calendar.connect();
    await kit.hub.sync.syncOnOpen();
    expect(
      (await kit.hub.store.ledger(
        connector: 'calendar',
      )).where((e) => e.action == LedgerAction.read),
      hasLength(1),
    );

    now = now.add(const Duration(minutes: 3));
    expect((await kit.hub.sync.syncOnOpen()).outcomes, isEmpty);
    expect((await kit.hub.sync.refresh()).outcomes.keys, ['calendar']);

    now = now.add(syncOnOpenMinInterval + const Duration(seconds: 1));
    expect((await kit.hub.sync.syncOnOpen()).outcomes.keys, ['calendar']);
  });

  test('concurrent callers share one run (single flight)', () async {
    await kit.hub.calendar.connect();
    final a = kit.hub.sync.refresh();
    final b = kit.hub.sync.refresh();
    expect(identical(a, b), isTrue);
    expect(kit.hub.sync.isRunning, isTrue);
    await a;
    expect(kit.hub.sync.isRunning, isFalse);
    expect(
      (await kit.hub.store.ledger(
        connector: 'calendar',
      )).where((e) => e.action == LedgerAction.read),
      hasLength(1),
    );
  });

  test('folder sync via the service respects charging-only', () async {
    kit.folder.nextPick = const FolderGrant(id: 'g', name: 'Notes');
    kit.folder.addFile('a.txt', 'alpha');
    await kit.hub.folder.connect();
    kit.charging.value = false;
    var report = await kit.hub.sync.refresh();
    expect(report.outcomes['folder']!.result!.skipped, isNotNull);
    expect(await kit.hub.store.countItems('folder'), 0);
    kit.charging.value = true;
    report = await kit.hub.sync.refresh();
    expect(report.outcomes['folder']!.result!.read, 1);
  });

  test('status streams announce syncing then the settled state', () async {
    await kit.hub.calendar.connect();
    final seen = <ConnectorState>[];
    final sub = kit.hub.calendar.status.listen((s) => seen.add(s.state));
    await kit.hub.calendar.sync();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first, ConnectorState.syncing);
    expect(seen.last, ConnectorState.connected);
  });

  group('background job body', () {
    test('runs a full refresh and reports success', () async {
      await kit.hub.calendar.connect();
      expect(await runConnectorSync(kit.hub), isTrue);
      expect(await kit.hub.store.countItems('calendar'), 1);
    });

    test('reports success even when a source fails (no battery-draining '
        'retry loop)', () async {
      await kit.hub.calendar.connect();
      kit.calendar.failRead = true;
      expect(await runConnectorSync(kit.hub), isTrue);
    });
  });
}
