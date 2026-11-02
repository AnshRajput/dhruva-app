// Wave 5 polish: one row per document (attached + folder copy), and the
// "N can't be searched" count opens into names, reasons and fixes.

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart' show FolderFile;
import 'package:dhruva/data/docs/document_repository.dart' show DocumentInfo;
import 'package:dhruva/features/library/state/library_documents.dart';
import 'package:dhruva/features/library/state/library_text.dart';
import 'package:dhruva/features/library/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/connector_ui_harness.dart';

DocumentInfo _doc(int id, String name, {int pages = 0, int day = 1}) =>
    DocumentInfo(
      id: id,
      conversationId: id,
      name: name,
      mime: 'application/pdf',
      pageCount: pages,
      charCount: 100,
      createdAt: DateTime(2026, 11, day),
    );

FolderFile _file(String name, {int? pages}) => FolderFile(
  itemId: 1,
  fileId: 'doc:$name',
  name: name,
  modified: null,
  pages: pages,
  problem: null,
);

void main() {
  group('dedupeAttached', () {
    test('an attached file and its folder copy are one document', () {
      final out = dedupeAttached(
        [_doc(1, 'Rental-Agreement.pdf', pages: 2)],
        [_file('rental-agreement.pdf', pages: 2)],
      );
      expect(out, isEmpty, reason: 'the folder row is the one that stays');
    });

    test('a folder copy with unknown pages still matches by name', () {
      final out = dedupeAttached(
        [_doc(1, 'lease.pdf', pages: 3)],
        [_file('lease.pdf')],
      );
      expect(out, isEmpty);
    });

    test('same name but a different page count is a different document', () {
      final out = dedupeAttached(
        [_doc(1, 'notes.pdf', pages: 5)],
        [_file('notes.pdf', pages: 2)],
      );
      expect(out, hasLength(1));
    });

    test('the same file attached to two chats shows once, newest first', () {
      final out = dedupeAttached([
        _doc(1, 'q4.pdf', pages: 4),
        _doc(2, 'q4.pdf', pages: 4, day: 2),
        _doc(3, 'other.pdf', pages: 1),
      ], const []);
      expect(out.map((d) => d.id), [2, 3]);
    });
  });

  test('unreadableFix gives every reason a next step', () {
    for (final k in [
      'tooLarge',
      'tooLong',
      'empty',
      'noText',
      'encrypted',
      'unsupported',
      'unsafe',
      'whatever',
    ]) {
      expect(unreadableFix(k), isNotEmpty, reason: k);
    }
  });

  testWidgets("\"N can't be searched\" expands to names, reasons and fixes", (
    tester,
  ) async {
    final ui = await pumpConnectorScreen(tester, const LibraryScreen());
    await seedFolder(ui, {'ok.md': 'fine text'});
    await ui.kit.hub.store.upsertItems(ConnectorIds.folder, [
      ItemDraft(
        externalId: 'doc:scan.pdf',
        kind: ItemKind.file,
        title: 'scan.pdf',
        body: '',
        sentAt: DateTime.now(),
        flags: {
          'fileId': 'doc:scan.pdf',
          'mtime': 1,
          'size': 10,
          'name': 'scan.pdf',
          'mime': 'application/pdf',
          'unreadable': 'noText',
        },
      ),
    ]);
    await ui.kit.hub.store.saveAccount(
      ConnectorIds.folder,
      config: {'grantId': 'tree:1', 'name': 'Documents/Notes', 'total': 2},
    );
    await ui.kit.hub.folder.refreshStatus();
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('library-unreadable-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.text("1 can't be searched"), findsOneWidget);
    expect(find.textContaining('searchable PDF'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('library-unreadable-doc:scan.pdf')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Scanned pages, no text to read.'),
      findsOneWidget,
    );
    expect(find.textContaining('searchable PDF'), findsOneWidget);
  });
}
