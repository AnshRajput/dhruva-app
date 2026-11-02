// Wave 5 data-integrity fixes: M2 (one sync at a time per connector), M3 (the
// folder index survives a transient empty / cut-off / much smaller listing),
// M4 (a reindexed file is replaced in one transaction, ids stay stable).

import 'dart:async';

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
    kit.folder.nextPick = const FolderGrant(id: 'tree:notes', name: 'Notes');
  });
  tearDown(() async {
    await kit.dispose();
    await db.close();
  });

  group('M2: one sync at a time per connector', () {
    test('overlapping sync() calls join one run: one read, one ledger '
        'row, same result', () async {
      kit.calendar
        ..perm = DevicePermission.granted
        ..items = [calEvent('e1', start: DateTime.utc(2026, 11, 2, 9))];
      await kit.hub.calendar.connect();
      final gate = Completer<void>();
      kit.calendar
        ..eventsGate = gate
        ..eventsCalls = 0;

      final a = kit.hub.calendar.sync();
      final b = kit.hub.calendar.sync();
      final c = kit.hub.calendar.sync();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      final results = await Future.wait([a, b, c]);

      expect(kit.calendar.eventsCalls, 1);
      expect(results.map((r) => r.read).toSet(), hasLength(1));
      final reads = (await kit.hub.store.ledger(
        connector: 'calendar',
      )).where((e) => e.action == LedgerAction.read);
      expect(reads, hasLength(1));
      // And the next sync, after the first finished, is a fresh run.
      kit.calendar.eventsGate = null;
      await kit.hub.calendar.sync();
      expect(kit.calendar.eventsCalls, 2);
    });

    test('revoke waits for the running sync even when a second call joined '
        'it', () async {
      kit.calendar
        ..perm = DevicePermission.granted
        ..items = [calEvent('e1', start: DateTime.utc(2026, 11, 2, 9))];
      await kit.hub.calendar.connect();
      final gate = Completer<void>();
      kit.calendar.eventsGate = gate;
      final a = kit.hub.calendar.sync();
      final b = kit.hub.calendar.sync();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var revoked = false;
      final revoke = kit.hub.calendar.revoke().then((_) => revoked = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(revoked, isFalse, reason: 'still waiting for the sync');
      gate.complete();
      await Future.wait([a.catchError((_) => const SyncResult()), b, revoke]);
      expect(await kit.hub.store.countItems('calendar'), 0);
      expect(await kit.hub.store.account('calendar'), isNull);
    });

    test('a sync on a connector that is not connected still throws', () async {
      await expectLater(
        kit.hub.calendar.sync(),
        throwsA(isA<ConnectorException>()),
      );
      // ...and does not leave the connector stuck "syncing".
      await expectLater(
        kit.hub.calendar.sync(),
        throwsA(isA<ConnectorException>()),
      );
    });
  });

  group('M3: the folder index is not wiped by an untrustworthy listing', () {
    Future<void> indexed(int n) async {
      for (var i = 0; i < n; i++) {
        kit.folder.addFile('f$i.txt', 'text number $i', id: 'e$i');
      }
      await kit.hub.folder.connect();
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), n);
    }

    test('an empty listing removes nothing the first time', () async {
      await indexed(3);
      kit.folder.entries.clear(); // provider offline: empty, "successful"
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 3);
    });

    test('the same empty listing seen again minutes later is still held '
        '(an offline provider fails twice in a row)', () async {
      await indexed(3);
      kit.folder.entries.clear();
      await kit.hub.folder.indexNow();
      now = now.add(const Duration(minutes: 10));
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 3);
    });

    test('the same empty listing seen again an hour later is believed (the '
        'user really emptied the folder)', () async {
      await indexed(3);
      kit.folder.entries.clear();
      await kit.hub.folder.indexNow();
      now = now.add(const Duration(hours: 1, minutes: 1));
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 0);
    });

    test('a transient empty listing followed by a good one keeps the index '
        'and clears the hold', () async {
      await indexed(3);
      final saved = Map.of(kit.folder.entries);
      kit.folder.entries.clear();
      await kit.hub.folder.indexNow();
      kit.folder.entries.addAll(saved);
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 3);
      expect(
        (await kit.hub.store.account(
          'folder',
        ))!.config.containsKey('pruneHold'),
        isFalse,
      );
      // A later real deletion is still pruned (one file of three is not
      // "suspicious" below 8 files).
      kit.folder.entries.remove('e0');
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 2);
    });

    test('a listing that suddenly lost most of a bigger folder is held, '
        'then believed if it repeats', () async {
      await indexed(10);
      for (var i = 0; i < 8; i++) {
        kit.folder.entries.remove('e$i');
      }
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 10);
      now = now.add(const Duration(hours: 2));
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 2);
    });

    test('a small, ordinary deletion is pruned straight away', () async {
      await indexed(10);
      kit.folder.entries.remove('e9');
      await kit.hub.folder.indexNow();
      expect(await kit.hub.store.countItems('folder'), 9);
    });
  });

  group('M4: a reindexed file is replaced atomically', () {
    test('row ids of surviving sections are stable across a reindex', () async {
      kit.folder.addFile('a.txt', 'first version', id: 'a');
      await kit.hub.folder.connect();
      await kit.hub.folder.indexNow();
      final before = await kit.hub.store.itemsOf('folder');
      expect(before, hasLength(1));

      kit.folder.addFile(
        'a.txt',
        'second version, now different',
        id: 'a',
        modified: DateTime.utc(2026, 11, 1),
      );
      await kit.hub.folder.indexNow();
      final after = await kit.hub.store.itemsOf('folder');
      expect(after, hasLength(1));
      expect(after.single.id, before.single.id, reason: 'chips keep working');
      expect(after.single.body, contains('second version'));
    });

    test('inTransaction rolls every write back when the body throws', () async {
      final store = kit.hub.store;
      await store.saveAccount('folder', config: const {'grantId': 'g'});
      await store.upsertItems('folder', [
        const ItemDraft(
          externalId: 'a',
          kind: ItemKind.file,
          title: 'a.txt',
          body: 'old',
        ),
      ]);
      await expectLater(
        store.inTransaction(() async {
          await store.removeByExternalIds('folder', ['a']);
          throw StateError('crash between the delete and the insert');
        }),
        throwsStateError,
      );
      expect(await store.countItems('folder'), 1);
      expect((await store.itemsOf('folder')).single.body, 'old');
    });
  });
}
