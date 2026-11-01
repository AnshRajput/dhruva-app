import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/connectors/folder_connector.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/docs/doc_chunker.dart';
import 'package:dhruva/data/docs/document_extractor.dart';
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

  Future<void> connect() => kit.hub.folder.connect();

  group('isIndexableName (path traversal / odd names)', () {
    test('accepts plain names with supported extensions', () {
      for (final ok in ['a.txt', 'Notes.MD', 'x.markdown', 'paper.PDF']) {
        expect(isIndexableName(ok), isTrue, reason: ok);
      }
    });
    test('rejects separators, traversal, NUL, wrong or no extension', () {
      for (final bad in [
        '',
        '../secret.txt',
        'a/b.txt',
        r'a\b.txt',
        'a\u0000.txt',
        '..',
        '.',
        'image.png',
        'noext',
        '.txt'.padRight(300, 'x'),
        'script.sh',
      ]) {
        expect(isIndexableName(bad), isFalse, reason: bad);
      }
    });
  });

  group('connect / status', () {
    test('picking a folder connects it; nothing is indexed yet', () async {
      await connect();
      expect(kit.hub.folder.currentStatus.state, ConnectorState.connected);
      final a = (await kit.hub.store.account('folder'))!;
      expect(a.config['grantId'], 'tree:notes');
      expect(a.label, 'Notes');
      expect(kit.folder.listCalls, 0);
      expect(await kit.hub.store.countItems('folder'), 0);
    });

    test('cancelling the picker leaves things as they were', () async {
      kit.folder.nextPick = null;
      await connect();
      expect(kit.hub.folder.currentStatus.state, ConnectorState.notConnected);
      expect(await kit.hub.store.account('folder'), isNull);
    });

    test('choosing a different folder releases the old grant', () async {
      await connect();
      kit.folder.nextPick = const FolderGrant(id: 'tree:other', name: 'Other');
      await connect();
      expect(kit.folder.released, ['tree:notes']);
      expect(
        (await kit.hub.store.account('folder'))!.config['grantId'],
        'tree:other',
      );
    });

    test('a folder that vanished needs attention and names the fix', () async {
      await connect();
      kit.folder.reachable = false;
      await kit.hub.folder.refreshStatus();
      final s = kit.hub.folder.currentStatus;
      expect(s.state, ConnectorState.needsAttention);
      expect(s.detail, contains('Choose it again'));
    });
  });

  group('indexing policy: explicit request or charging only', () {
    setUp(() {
      kit.folder.addFile('a.txt', 'Hotel prices in Pune are rising.');
    });

    test('on battery, a scheduled sync indexes nothing (and writes no read '
        'ledger row)', () async {
      await connect();
      kit.charging.value = false;
      final r = await kit.hub.folder.sync();
      expect(r.skipped, contains('charging'));
      expect(kit.folder.listCalls, 0);
      expect(await kit.hub.store.countItems('folder'), 0);
      final actions = (await kit.hub.store.ledger(
        connector: 'folder',
      )).map((e) => e.action);
      expect(actions, isNot(contains(LedgerAction.read)));
    });

    test('while charging, a scheduled sync indexes', () async {
      await connect();
      kit.charging.value = true;
      final r = await kit.hub.folder.sync();
      expect(r.read, 1);
      expect(await kit.hub.store.countItems('folder'), 1);
    });

    test('"index now" works on battery', () async {
      await connect();
      kit.charging.value = false;
      final r = await kit.hub.folder.indexNow();
      expect(r.read, 1);
      // ...but the next scheduled sync is back to charging-only.
      expect((await kit.hub.folder.sync()).skipped, isNotNull);
    });

    test(
      'unplugging mid-run stops a scheduled index and keeps the progress',
      () async {
        for (var i = 0; i < 30; i++) {
          kit.folder.addFile('f$i.txt', 'text number $i about pune');
        }
        await connect();
        // Check 1 (policy gate): charging. Check 2 (after 10 files): unplugged.
        kit.charging.script = [true, false];
        final r = await kit.hub.folder.sync();
        expect(r.read, 10);
        expect(await kit.hub.store.countItems('folder'), 10);
      },
    );
  });

  group('indexing', () {
    test(
      'indexes text files into searchable sections, with metadata',
      () async {
        kit.folder.addFile(
          'trip.md',
          '# Pune trip\nBook the hotel near Shivajinagar.',
        );
        kit.folder.addFile('todo.txt', 'Renew passport');
        await connect();
        final r = await kit.hub.folder.indexNow();
        expect(r.read, 2);
        final items = await kit.hub.store.itemsOf('folder');
        expect(
          items.map((i) => i.title),
          unorderedEquals(['trip.md', 'todo.txt']),
        );
        final trip = items.firstWhere((i) => i.title == 'trip.md');
        expect(trip.body, contains('Shivajinagar'));
        expect(trip.flags['size'], isA<int>());
        expect(trip.flags['mtime'], isA<int>());
        expect(trip.kind, ItemKind.file);
        // Temp copies are gone.
        final cache = Directory('${kit.tempDir.path}/cache');
        expect(
          cache.existsSync() ? cache.listSync() : <FileSystemEntity>[],
          isEmpty,
        );
      },
    );

    test(
      'unchanged files are skipped next time; changed ones are re-read',
      () async {
        kit.folder.addFile('a.txt', 'alpha', id: 'a');
        kit.folder.addFile('b.txt', 'bravo', id: 'b');
        await connect();
        await kit.hub.folder.indexNow();
        kit.folder.fetched.clear();

        expect((await kit.hub.folder.indexNow()).read, 0);
        expect(kit.folder.fetched, isEmpty);

        kit.folder.addFile(
          'a.txt',
          'alpha two',
          id: 'a',
          modified: DateTime.utc(2026, 11, 1),
        );
        expect((await kit.hub.folder.indexNow()).read, 1);
        expect(kit.folder.fetched, ['a']);
        expect(
          (await kit.hub.store.itemsOf(
            'folder',
          )).firstWhere((i) => i.externalId == 'a').body,
          'alpha two',
        );
      },
    );

    test('a deleted file leaves the index', () async {
      kit.folder.addFile('a.txt', 'alpha', id: 'a');
      kit.folder.addFile('b.txt', 'bravo', id: 'b');
      await connect();
      await kit.hub.folder.indexNow();
      kit.folder.entries.remove('b');
      await kit.hub.folder.indexNow();
      expect((await kit.hub.store.itemsOf('folder')).map((i) => i.externalId), [
        'a',
      ]);
    });

    test(
      'a long file becomes several 8 KB sections, capped per file',
      () async {
        final para = 'word ' * 150; // ~750 chars
        kit.folder.addFile(
          'long.txt',
          List.filled(120, para).join('\n\n'),
          id: 'long',
        );
        await connect();
        await kit.hub.folder.indexNow();
        final items = await kit.hub.store.itemsOf('folder');
        expect(items.length, maxSectionsPerFile);
        expect(
          items.map((i) => i.externalId),
          containsAll(['long', 'long#2', 'long#6']),
        );
        for (final i in items) {
          expect(i.body.length, lessThanOrEqualTo(maxItemBodyChars));
        }
        // Re-indexing a changed file replaces all of its sections.
        kit.folder.addFile(
          'long.txt',
          'short now',
          id: 'long',
          modified: DateTime.utc(2026, 11, 1),
        );
        await kit.hub.folder.indexNow();
        expect(
          (await kit.hub.store.itemsOf('folder')).single.body,
          'short now',
        );
      },
    );

    test(
      'a file that cannot be copied out gets a findable-by-name placeholder '
      'and is retried next sync until it works; the rest still index',
      () async {
        kit.folder.addFile('good.txt', 'fine', id: 'good');
        kit.folder.addFile('bad.txt', 'recovered text', id: 'bad');
        kit.folder.unreadable.add('bad');
        await connect();
        final r = await kit.hub.folder.indexNow();
        expect(r.read, 2);
        final bad = (await kit.hub.store.itemsOf(
          'folder',
        )).firstWhere((i) => i.externalId == 'bad');
        expect(bad.flags['unreadable'], 'unreadable');
        expect(bad.flags['retry'], true);
        expect(bad.title, 'bad.txt'); // still findable by name

        // Unchanged file, but the failure was transient: tried again.
        kit.folder.fetched.clear();
        await kit.hub.folder.indexNow();
        expect(kit.folder.fetched, ['bad']);

        kit.folder.unreadable.clear();
        await kit.hub.folder.indexNow();
        final fixed = (await kit.hub.store.itemsOf(
          'folder',
        )).firstWhere((i) => i.externalId == 'bad');
        expect(fixed.body, 'recovered text');
        expect(fixed.flags['unreadable'], isNull);
        kit.folder.fetched.clear();
        await kit.hub.folder.indexNow();
        expect(kit.folder.fetched, isEmpty);
      },
    );

    test('a transient failure on an already-indexed, changed file keeps its '
        'old text', () async {
      kit.folder.addFile('a.txt', 'old words', id: 'a');
      await connect();
      await kit.hub.folder.indexNow();
      kit.folder.addFile(
        'a.txt',
        'new words',
        id: 'a',
        modified: DateTime.utc(2026, 11, 1),
      );
      kit.folder.unreadable.add('a');
      await kit.hub.folder.indexNow();
      expect((await kit.hub.store.itemsOf('folder')).single.body, 'old words');
    });

    test('a deterministic extraction failure (e.g. a scanned PDF) is a '
        'placeholder and is NOT retried', () async {
      final stub = ConnectorTestKit.create(
        db,
        extractor: (path, name) async => throw const DocumentException(
          DocumentFailureKind.noText,
          'No text layer.',
        ),
      );
      addTearDown(stub.dispose);
      stub.folder.nextPick = const FolderGrant(id: 'g', name: 'Scans');
      stub.folder.addFile('scan.pdf', 'x', id: 'scan');
      await stub.hub.folder.connect();
      await stub.hub.folder.indexNow();
      final item = (await stub.hub.store.itemsOf('folder')).single;
      expect(item.flags['unreadable'], 'noText');
      expect(item.flags['retry'], isNull);
      stub.folder.fetched.clear();
      await stub.hub.folder.indexNow();
      expect(stub.folder.fetched, isEmpty);
    });

    test('a "#" in a file name does not confuse sections with files '
        '(no churn, no wrong deletes)', () async {
      kit.folder.addFile('C#notes.md', 'sharp notes', id: 'dir/C#notes.md');
      kit.folder.addFile('C.md', 'plain', id: 'C');
      await connect();
      await kit.hub.folder.indexNow();
      kit.folder.fetched.clear();
      expect((await kit.hub.folder.indexNow()).read, 0);
      expect(kit.folder.fetched, isEmpty);
      expect(
        (await kit.hub.store.itemsOf('folder')).map((i) => i.externalId),
        unorderedEquals(['dir/C#notes.md', 'C']),
      );
    });

    test(
      'unsupported types and traversal-style names are never fetched',
      () async {
        kit.folder.addFile('photo.png', 'x', id: 'p1');
        kit.folder.addFile('../escape.txt', 'x', id: 'p2');
        kit.folder.addFile('ok.txt', 'ok', id: 'p3');
        await connect();
        await kit.hub.folder.indexNow();
        expect(kit.folder.fetched, ['p3']);
      },
    );

    test('a file over 20 MB is not fetched; it gets a placeholder', () async {
      kit.folder.entries['huge'] = FolderEntry(
        id: 'huge',
        name: 'huge.pdf',
        size: maxDocumentBytes + 1,
        modified: DateTime.utc(2026, 10, 1),
      );
      kit.folder.files['huge'] = Uint8List(1);
      await connect();
      await kit.hub.folder.indexNow();
      expect(kit.folder.fetched, isEmpty);
      expect(
        (await kit.hub.store.itemsOf('folder')).single.flags['unreadable'],
        'tooLarge',
      );
    });

    test('at most $maxFolderFiles files are indexed, even if the native side '
        'returns more', () async {
      // A stub extractor: this test is about the cap, not parsing.
      final stub = ConnectorTestKit.create(
        db,
        extractor: (path, name) async => ExtractedDocument(
          name: name,
          mime: 'text/plain',
          pageCount: 0,
          charCount: 1,
          chunks: const [DocChunk(index: 0, page: 1, text: 'x')],
        ),
      );
      addTearDown(stub.dispose);
      stub.folder.ignoreMaxFiles = true;
      stub.folder.nextPick = const FolderGrant(id: 'g', name: 'Big');
      for (var i = 0; i < maxFolderFiles + 5; i++) {
        stub.folder.addFile('n$i.txt', 'hello $i', id: 'e$i');
      }
      await stub.hub.folder.connect();
      final r = await stub.hub.folder.indexNow();
      expect(r.read, maxFolderFiles);
      expect(stub.folder.fetched.length, maxFolderFiles);
      // 2,000 DB writes: slow on a loaded CI box, so the default 30 s is not
      // a safe bound.
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'a listing failure is a needs-attention card; the index is kept',
      () async {
        kit.folder.addFile('a.txt', 'alpha', id: 'a');
        await connect();
        await kit.hub.folder.indexNow();
        kit.folder.failList = true;
        await expectLater(
          kit.hub.folder.indexNow(),
          throwsA(isA<ConnectorException>()),
        );
        expect(await kit.hub.store.countItems('folder'), 1);
        expect(
          kit.hub.folder.currentStatus.state,
          ConnectorState.needsAttention,
        );
      },
    );

    test(
      'a vanished folder fails the sync with the choose-again card',
      () async {
        await connect();
        kit.folder.reachable = false;
        await expectLater(
          kit.hub.folder.indexNow(),
          throwsA(isA<ConnectorException>()),
        );
      },
    );
  });

  group('revoke', () {
    test('releases the OS grant, deletes the index and ledger content, keeps '
        'a revoke row', () async {
      kit.folder.addFile('a.txt', 'alpha', id: 'a');
      await connect();
      await kit.hub.folder.indexNow();
      await kit.hub.folder.revoke();
      expect(kit.folder.released, ['tree:notes']);
      expect(await kit.hub.store.countItems('folder'), 0);
      expect(await kit.hub.store.account('folder'), isNull);
      expect(
        (await kit.hub.store.ledger(connector: 'folder')).map((e) => e.action),
        [LedgerAction.revoke],
      );
      expect(kit.hub.folder.currentStatus.state, ConnectorState.notConnected);
    });

    test('revoke during a running index leaves no items, no account and only '
        'the revoke ledger row', () async {
      for (var i = 0; i < 3; i++) {
        kit.folder.addFile('f$i.txt', 'text $i', id: 'f$i');
      }
      await connect();
      kit.folder.fetchGate = Completer<void>();
      kit.folder.fetchStarted = Completer<void>();
      final index = kit.hub.folder.indexNow();
      await kit.folder.fetchStarted!.future;
      final revoke = kit.hub.folder.revoke();
      kit.folder.fetchGate!.complete();
      await index;
      await revoke;
      expect(await kit.hub.store.countItems('folder'), 0);
      expect(await kit.hub.store.account('folder'), isNull);
      expect(
        (await kit.hub.store.ledger(connector: 'folder')).map((e) => e.action),
        [LedgerAction.revoke],
      );
      expect(kit.hub.folder.currentStatus.state, ConnectorState.notConnected);
    });

    test('revoke still wipes locally if releasing the grant throws', () async {
      kit.folder.addFile('a.txt', 'alpha', id: 'a');
      await connect();
      await kit.hub.folder.indexNow();
      kit.folder.failRelease = true;
      await kit.hub.folder.revoke();
      expect(await kit.hub.store.countItems('folder'), 0);
      expect(await kit.hub.store.account('folder'), isNull);
    });
  });

  test(
    'real doc-chat extractor reads a text file through the isolate',
    () async {
      final realKit = ConnectorTestKit.create(
        db,
        clock: () => DateTime.utc(2026, 11, 1, 8),
      );
      addTearDown(realKit.dispose);
      // ConnectorTestKit uses the production extractor by default.
      realKit.folder.nextPick = const FolderGrant(id: 'g', name: 'Docs');
      realKit.folder.addFile(
        'real.md',
        '# Heading\n\nA paragraph about mountains.',
      );
      await realKit.hub.folder.connect();
      await realKit.hub.folder.indexNow();
      final item = (await realKit.hub.store.itemsOf('folder')).single;
      expect(item.body, contains('mountains'));
      expect(item.flags['mime'], isNotNull);
    },
  );
}
