// Wave 3B: the Library. Folder block, file search results, opening a file and
// asking about it, saved answers, to-dos persistence, empty states.

import 'package:dhruva/core/di/library_providers.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/connectors/search_index.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/library/ui/file_search_screen.dart';
import 'package:dhruva/features/library/ui/library_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/connector_ui_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

SearchHit _hit(int id, String fileId) => SearchHit(
  ConnectorItem(
    id: id,
    source: 'folder',
    externalId: '$fileId#$id',
    kind: ItemKind.file,
    title: fileId,
    body: '',
    people: const [],
    startsAt: null,
    sentAt: null,
    flags: {'fileId': fileId},
    summary: null,
    summaryModel: null,
    updatedAt: DateTime(2026, 11, 2),
  ),
  1,
);

ConversationsCompanion _conversation() => ConversationsCompanion.insert(
  createdAt: DateTime(2026, 11, 2),
  updatedAt: DateTime(2026, 11, 2),
);

AttachedDocumentsCompanion _doc(
  int conversationId,
  String name, {
  int pages = 0,
}) => AttachedDocumentsCompanion.insert(
  conversationId: conversationId,
  name: name,
  mime: 'application/pdf',
  pageCount: Value(pages),
  createdAt: DateTime(2026, 11, 2),
);

Future<ConnectorUi> _connectFolder(
  WidgetTester tester,
  Widget home, {
  Map<String, String> files = const {},
  int? total,
}) async {
  final ui = await pumpConnectorScreen(tester, home);
  await seedFolder(ui, files, total: total);
  await ui.kit.hub.folder.refreshStatus();
  await tester.pumpAndSettle();
  return ui;
}

void main() {
  group('Library, nothing connected', () {
    testWidgets('every section has an empty state with a next step', (
      tester,
    ) async {
      await pumpConnectorScreen(tester, const LibraryScreen());
      expect(_key('library-connect-folder'), findsOneWidget);
      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('No to-dos yet'), findsOneWidget);
      expect(find.text('Nothing saved yet'), findsOneWidget);
      for (final k in [
        'library-documents-action',
        'library-todos-action',
        'library-saved-action',
      ]) {
        expect(_key(k), findsOneWidget, reason: k);
      }
    });

    testWidgets('tapping "Connect a folder" opens the system picker', (
      tester,
    ) async {
      final ui = await pumpConnectorScreen(tester, const LibraryScreen());
      ui.kit.folder.nextPick = const FolderGrant(
        id: 'tree:9',
        name: 'Documents/Notes',
      );
      await tester.tap(_key('library-connect-folder'));
      await tester.pumpAndSettle();
      expect(_key('library-folder-block'), findsOneWidget);
      expect(find.text('Documents/Notes'), findsOneWidget);
      expect(find.text('Connected folder'), findsOneWidget);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final ui = await pumpConnectorScreen(tester, const LibraryScreen());
      ui.kit.folder.nextPick = null;
      await tester.tap(_key('library-connect-folder'));
      await tester.pumpAndSettle();
      expect(_key('library-connect-folder'), findsOneWidget);
    });
  });

  group('folder block', () {
    testWidgets('shows the index status in plain words and the files in '
        'Documents', (tester) async {
      final ui = await _connectFolder(
        tester,
        const LibraryScreen(),
        files: {
          'offsite.md': 'offsite ideas for Goa',
          'rental.txt': 'rental agreement text',
        },
      );
      expect(
        find.text('All 2 files ready to search'),
        findsOneWidget,
        reason: 'status headline',
      );
      expect(find.text('offsite.md'), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
      expect(find.text('TXT'), findsOneWidget);
      expect(_key('library-search-files'), findsOneWidget);
      await tester.tap(_key('library-search-files'));
      await tester.pumpAndSettle();
      expect(ui.visited, ['/library/search']);
    });

    testWidgets('still-indexing wording: "N of M files ready · finishes '
        'while charging"', (tester) async {
      // 312 of 340, as in the comp: 28 files are still waiting.
      final files = {for (var i = 0; i < 312; i++) 'note$i.md': 'text $i'};
      await _connectFolder(
        tester,
        const LibraryScreen(),
        files: files,
        total: 340,
      );
      expect(find.text('312 of 340 files ready to search'), findsOneWidget);
      expect(find.text('Finishes while charging'), findsOneWidget);
    });

    testWidgets('folder gone: the reason and Choose again, no Search', (
      tester,
    ) async {
      final ui = await _connectFolder(
        tester,
        const LibraryScreen(),
        files: {'a.md': 'alpha'},
      );
      ui.kit.folder.reachable = false;
      await ui.kit.hub.folder.refreshStatus();
      await tester.pumpAndSettle();
      expect(_key('library-folder-problem'), findsOneWidget);
      expect(find.textContaining('no longer available'), findsOneWidget);
      expect(_key('library-search-files'), findsNothing);
      expect(find.text('Choose again'), findsOneWidget);
    });
  });

  group('file search', () {
    testWidgets('results list file name, snippet and page; the sheet opens '
        'the file in the OS viewer', (tester) async {
      final ui = await _connectFolder(
        tester,
        const FileSearchScreen(),
        files: {
          'budget.md':
              'The Q4 budget needs approval from finance before '
              'the offsite in Goa.',
          'other.txt': 'Nothing about money here, only lunch plans.',
        },
      );
      await tester.enterText(_key('file-search-field'), 'budget');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('budget.md'), findsOneWidget);
      expect(find.text('other.txt'), findsNothing);
      expect(find.textContaining('Q4 budget needs approval'), findsOneWidget);

      await tester.tap(find.text('budget.md'));
      await tester.pumpAndSettle();
      await tester.tap(_key('file-open'));
      await tester.pumpAndSettle();
      expect(ui.opener.opened, [('tree:1', 'doc:budget.md')]);
    });

    testWidgets('the OS viewer failing names the reason', (tester) async {
      final ui = await _connectFolder(
        tester,
        const FileSearchScreen(),
        files: {'budget.md': 'the budget'},
      );
      ui.opener.failure = const OpenFailure(
        'No app on this phone can open that file.',
      );
      await tester.enterText(_key('file-search-field'), 'budget');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('budget.md'));
      await tester.pumpAndSettle();
      await tester.tap(_key('file-open'));
      await tester.pumpAndSettle();
      expect(
        find.text('No app on this phone can open that file.'),
        findsOneWidget,
      );
    });

    testWidgets('"Ask about this file" opens a new chat with the file as '
        'its source', (tester) async {
      final ui = await _connectFolder(
        tester,
        const FileSearchScreen(),
        files: {'budget.md': 'The Q4 budget needs approval.'},
      );
      await tester.enterText(_key('file-search-field'), 'budget');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('budget.md'));
      await tester.pumpAndSettle();
      await tester.tap(_key('file-ask'));
      await tester.pumpAndSettle();
      final sections = await ui.kit.hub.store.fileSections('doc:budget.md');
      expect(sections, hasLength(1));
      expect(ui.visited, ['/chat/new?source=${sections.single.id}']);
    });

    testWidgets('no match says what to try; empty query hints; no folder '
        'offers Connectors', (tester) async {
      final ui = await _connectFolder(
        tester,
        const FileSearchScreen(),
        files: {'a.md': 'alpha beta'},
      );
      expect(find.text('Search inside your files'), findsOneWidget);
      await tester.enterText(_key('file-search-field'), 'zebra');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('No file matches "zebra"'), findsOneWidget);

      await ui.kit.hub.folder.revoke();
      await tester.pumpAndSettle();
      expect(find.text('Connect a folder to search it'), findsOneWidget);
      await tester.tap(_key('search-connect'));
      await tester.pumpAndSettle();
      expect(ui.visited, ['/settings/connectors']);
    });

    test('one result per file, best section first', () {
      // bestHitPerFile keeps the first (best) hit of each file id.
      final a1 = _hit(1, 'f1');
      final a2 = _hit(2, 'f1');
      final b = _hit(3, 'f2');
      expect(bestHitPerFile([a1, b, a2]).map((h) => h.item.id), [1, 3]);
    });
  });

  group('Documents', () {
    testWidgets('attached chat documents appear with page counts and open '
        'their chat', (tester) async {
      final ui = await pumpConnectorScreen(tester, const LibraryScreen());
      final convo = await ui.db
          .into(ui.db.conversations)
          .insert(_conversation());
      await ui.db
          .into(ui.db.attachedDocuments)
          .insert(_doc(convo, 'Rental agreement, Indiranagar.pdf', pages: 14));
      await tester.pumpAndSettle();
      expect(find.text('Rental agreement, Indiranagar.pdf'), findsOneWidget);
      expect(find.text('14 pages · attached to Ask'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      await tester.tap(find.text('Rental agreement, Indiranagar.pdf'));
      await tester.pumpAndSettle();
      expect(ui.visited, ['/chat/$convo']);
    });
  });

  group('To-dos', () {
    testWidgets('added items persist, check off, delete', (tester) async {
      final ui = await pumpConnectorScreen(tester, const LibraryScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryScreen)),
      );
      final store = container.read(libraryStoreProvider);
      expect(
        await store.addTodos([
          'Send revised invoice to Sofia',
          'Confirm Goa dates with Marcus',
        ]),
        2,
      );
      await tester.pumpAndSettle();
      expect(find.text('Send revised invoice to Sofia'), findsOneWidget);
      expect(find.text('2 open'), findsOneWidget);

      // Check off the first.
      final first = (await ui.db.select(ui.db.todos).get()).first;
      await tester.tap(_key('todo-check-${first.id}'));
      await tester.pumpAndSettle();
      expect(find.text('1 open'), findsOneWidget);
      expect(_key('todos-clear-done'), findsOneWidget);

      // Persisted: a fresh store over the same DB sees the state.
      final again = await ui.db.select(ui.db.todos).get();
      expect(again.firstWhere((t) => t.id == first.id).done, isTrue);

      // Delete the other.
      final other = again.firstWhere((t) => !t.done);
      await tester.tap(_key('todo-delete-${other.id}'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Goa dates with Marcus'), findsNothing);

      // Clear done -> back to the empty state with its next step.
      await tester.tap(_key('todos-clear-done'));
      await tester.pumpAndSettle();
      expect(find.text('No to-dos yet'), findsOneWidget);
      expect(ui.db, isNotNull);
    });
  });

  group('Saved', () {
    testWidgets('a saved reply is listed, readable, copyable and deletable', (
      tester,
    ) async {
      await pumpConnectorScreen(tester, const LibraryScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryScreen)),
      );
      final store = container.read(libraryStoreProvider);
      await store.saveAnswer(
        'Reply to Marcus about Goa\n\nHi Marcus, 14-15 Dec works.',
      );
      // Saving the same text twice keeps one copy.
      await store.saveAnswer(
        'Reply to Marcus about Goa\n\nHi Marcus, 14-15 Dec works.',
      );
      await tester.pumpAndSettle();
      expect(find.text('Reply to Marcus about Goa'), findsOneWidget);
      await tester.tap(find.text('Reply to Marcus about Goa'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hi Marcus, 14-15 Dec works.'),
        findsOneWidget,
      );
      await tester.tap(_key('saved-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing saved yet'), findsOneWidget);
    });
  });
}
