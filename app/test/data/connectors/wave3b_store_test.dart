// Wave 3B additions to the connectors data layer: cancelling a manual index,
// the folder's file total, the user's "read" mark surviving a re-ingest, the
// folder-file and notification watchers, ledger clearing, resume handling, and
// the pure index-status wording.

import 'dart:async';

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/connectors/folder_index_status.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_connector_sources.dart';

void main() {
  late AppDatabase db;
  late ConnectorTestKit kit;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    kit = ConnectorTestKit.create(
      db,
      clock: () => DateTime.utc(2026, 11, 1, 8),
    );
    kit.folder.nextPick = const FolderGrant(id: 'tree:notes', name: 'Notes');
  });
  tearDown(() async {
    await kit.dispose();
    await db.close();
  });

  group('folder index: cancel and total', () {
    test('cancelSync stops a manual index after the file in flight; what is '
        'done stays', () async {
      for (var i = 0; i < 3; i++) {
        kit.folder.addFile('f$i.txt', 'text $i', id: 'f$i');
      }
      await kit.hub.folder.connect();
      kit.folder.fetchGate = Completer<void>();
      kit.folder.fetchStarted = Completer<void>();
      final index = kit.hub.folder.indexNow();
      await kit.folder.fetchStarted!.future;
      kit.hub.folder.cancelSync();
      kit.folder.fetchGate!.complete();
      final result = await index;
      expect(result.read, 1);
      expect(kit.folder.fetched, hasLength(1));
      // The first file is searchable, the account is still connected, and the
      // folder's total (what the status shows) was recorded.
      final files = await kit.hub.store.watchFolderFiles().first;
      expect(files.where((f) => f.ready), hasLength(1));
      final account = await kit.hub.store.account('folder');
      expect(account!.config['total'], 3);
      expect(kit.hub.folder.currentStatus.state, ConnectorState.connected);
    });

    test('cancelSync with nothing running does nothing, and a later index '
        'runs to the end', () async {
      kit.folder.addFile('a.txt', 'alpha', id: 'a');
      await kit.hub.folder.connect();
      kit.hub.folder.cancelSync();
      final r = await kit.hub.folder.indexNow();
      expect(r.read, 1);
    });
  });

  group('read mark', () {
    ItemDraft draft(String id, {String body = 'text'}) => ItemDraft(
      externalId: id,
      kind: ItemKind.notification,
      title: 'T',
      body: body,
      sentAt: DateTime.utc(2026, 11, 1, 7),
      flags: const {'pkg': 'p', 'app': 'App'},
    );

    test('setItemFlag sets and clears one key and keeps the rest', () async {
      final store = kit.hub.store;
      await store.upsertItems('notifications', [draft('a')]);
      final id = (await store.itemsOf('notifications')).single.id;
      await store.setItemFlag(id, 'read', true);
      var flags = (await store.itemsOf('notifications')).single.flags;
      expect(flags, {'pkg': 'p', 'app': 'App', 'read': true});
      await store.setItemFlag(id, 'read', null);
      flags = (await store.itemsOf('notifications')).single.flags;
      expect(flags, {'pkg': 'p', 'app': 'App'});
      await store.setItemFlag(9999, 'read', true); // gone: no throw
    });

    test('a re-ingested notification stays read, even when its text '
        'changed', () async {
      final store = kit.hub.store;
      await store.upsertItems('notifications', [draft('a')]);
      final id = (await store.itemsOf('notifications')).single.id;
      await store.setItemFlag(id, 'read', true);
      final same = await store.upsertItems('notifications', [draft('a')]);
      expect(same.unchanged, 1);
      await store.upsertItems('notifications', [draft('a', body: 'edited')]);
      final item = (await store.itemsOf('notifications')).single;
      expect(item.body, 'edited');
      expect(item.flags['read'], isTrue);
    });
  });

  group('watchers and helpers', () {
    test('watchFolderFiles: one entry per file, newest first, unreadable '
        'ones carry the reason', () async {
      final store = kit.hub.store;
      ItemDraft file(
        String id,
        String name,
        DateTime at, {
        int section = 1,
        String? problem,
      }) => ItemDraft(
        externalId: section == 1 ? id : '$id#$section',
        kind: ItemKind.file,
        title: name,
        body: 'body',
        sentAt: at,
        flags: {'fileId': id, 'section': section, 'unreadable': ?problem},
      );
      await store.upsertItems('folder', [
        file('old', 'old.md', DateTime.utc(2026, 10, 1)),
        file('new', 'new.md', DateTime.utc(2026, 10, 30)),
        file('new', 'new.md', DateTime.utc(2026, 10, 30), section: 2),
        file('big', 'big.pdf', DateTime.utc(2026, 10, 15), problem: 'tooLarge'),
      ]);
      final files = await store.watchFolderFiles().first;
      expect([for (final f in files) f.name], ['new.md', 'big.pdf', 'old.md']);
      expect(files[1].ready, isFalse);
      expect(files[1].problem, 'tooLarge');
    });

    test('fileSections returns every section of one file and not a '
        'neighbour whose id starts the same', () async {
      final store = kit.hub.store;
      ItemDraft d(String ext, String name) => ItemDraft(
        externalId: ext,
        kind: ItemKind.file,
        title: name,
        body: 'x',
        flags: {'fileId': ext.split('#').first},
      );
      await store.upsertItems('folder', [
        d('doc:1', 'a'),
        d('doc:1#2', 'a'),
        d('doc:10', 'b'),
      ]);
      final s = await store.fileSections('doc:1');
      expect([for (final i in s) i.externalId], ['doc:1', 'doc:1#2']);
    });

    test(
      'watchInbox: newest first (notifications and mail), only the window asked for',
      () async {
        final store = kit.hub.store;
        await store.upsertItems('notifications', [
          for (final (id, day) in [('a', 28), ('b', 31), ('c', 20)])
            ItemDraft(
              externalId: id,
              kind: ItemKind.notification,
              title: id,
              sentAt: DateTime.utc(2026, 10, day),
            ),
        ]);
        final recent = await store
            .watchInbox(since: DateTime.utc(2026, 10, 25))
            .first;
        expect([for (final i in recent) i.title], ['b', 'a']);
      },
    );

    test('clearLedger empties the history and nothing else', () async {
      final store = kit.hub.store;
      await store.upsertItems('calendar', [
        const ItemDraft(externalId: 'e', kind: ItemKind.event, title: 'x'),
      ]);
      await store.addLedger('calendar', LedgerAction.read, count: 1);
      await store.clearLedger();
      expect(await store.ledger(), isEmpty);
      expect(await store.countItems('calendar'), 1);
    });
  });

  group('onResume', () {
    test('picks up access granted in system settings: refreshes, reads right '
        'away, schedules the job', () async {
      final scheduler = FakeScheduler();
      final k = ConnectorTestKit.create(db, scheduler: scheduler);
      addTearDown(k.dispose);
      await k.hub.notifications.connect(); // not granted: needs attention
      expect(
        k.hub.notifications.currentStatus.state,
        ConnectorState.needsAttention,
      );
      expect(scheduler.scheduled, 0);
      k.notifications.granted = true;
      await k.hub.onResume();
      expect(k.hub.notifications.currentStatus.state, ConnectorState.connected);
      expect(scheduler.scheduled, 1);
      // It read straight away: the sync was recorded (an empty notification
      // read writes no ledger row, but it does stamp the last sync time).
      expect(
        (await k.hub.store.account('notifications'))!.lastSyncAt,
        isNotNull,
      );
    });

    test('access taken away is noticed and the job is cancelled when nothing '
        'is left', () async {
      final scheduler = FakeScheduler();
      final k = ConnectorTestKit.create(db, scheduler: scheduler);
      addTearDown(k.dispose);
      k.notifications.granted = true;
      await k.hub.notifications.connect();
      expect(scheduler.scheduled, 1);
      k.notifications.granted = false;
      await k.hub.onResume();
      expect(
        k.hub.notifications.currentStatus.state,
        ConnectorState.needsAttention,
      );
      expect(scheduler.cancelled, greaterThan(0));
    });
  });

  group('FolderIndexStatus wording', () {
    FolderIndexStatus s(int ready, int bad, int? total) =>
        FolderIndexStatus(ready: ready, unreadable: bad, total: total);

    test('the comp: 312 of 340, finishes while charging', () {
      expect(s(312, 0, 340).headline(), '312 of 340 files ready to search');
      expect(s(312, 0, 340).detail(indexing: false), 'Finishes while charging');
      expect(s(312, 0, 340).remaining, 28);
    });
    test('complete, with and without files that cannot be read', () {
      expect(s(340, 0, 340).headline(), 'All 340 files ready to search');
      expect(s(340, 0, 340).detail(indexing: false), 'Up to date');
      expect(
        s(338, 2, 340).detail(indexing: false),
        "2 can't be searched (too large, scanned or locked)",
      );
      expect(s(338, 2, 340).isComplete, isTrue);
    });
    test('unknown total, empty folder, indexing, fraction', () {
      expect(s(0, 0, null).headline(), 'Not indexed yet');
      expect(s(4, 0, null).headline(), '4 files ready to search');
      expect(s(0, 0, 0).headline(), 'No files found in this folder');
      expect(s(1, 0, 3).detail(indexing: true), 'Indexing now');
      expect(s(1, 0, 4).fraction, 0.25);
      expect(s(0, 0, null).fraction, isNull);
      expect(s(1, 0, 1).headline(), 'All 1 file ready to search');
    });
  });
}
