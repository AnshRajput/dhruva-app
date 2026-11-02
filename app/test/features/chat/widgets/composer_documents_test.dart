import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/docs/document_repository.dart';
import 'package:dhruva/features/chat/widgets/composer.dart';
import 'package:dhruva/voice/fake_mic_source.dart';
import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DocumentInfo doc(int id, String name, {int pages = 12, int chars = 14498}) =>
    DocumentInfo(
      id: id,
      conversationId: 1,
      name: name,
      mime: 'application/pdf',
      pageCount: pages,
      charCount: chars,
      createdAt: DateTime.utc(2026, 11, 1),
    );

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('composer_docs_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pump(
    WidgetTester tester, {
    bool isMultimodal = false,
    List<DocumentInfo> documents = const [],
    String? extractingDocName,
    String? documentError,
    VoidCallback? onAttachDocument,
    void Function(int)? onRemoveDocument,
    VoidCallback? onDismissDocumentError,
    VoidCallback? onCancelDocumentRead,
    bool disableAnimations = false,
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Composer(
              isGenerating: false,
              isMultimodal: isMultimodal,
              documents: documents,
              extractingDocName: extractingDocName,
              documentError: documentError,
              onAttachDocument: onAttachDocument,
              onRemoveDocument: onRemoveDocument,
              onDismissDocumentError: onDismissDocumentError,
              onCancelDocumentRead: onCancelDocumentRead,
              onSend: (_, _) {},
              onCancel: () {},
            ),
          ),
        ),
      ],
    );
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceModelInstallerProvider.overrideWith(
            (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
          ),
          voiceServiceProvider.overrideWithValue(FakeVoiceService()),
          micSourceProvider.overrideWithValue(FakeMicSource()),
        ],
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      ),
    );
  }

  testWidgets('without document support a text-only model has no attach '
      'button (unchanged behavior)', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Attach document'), findsNothing);
    expect(find.byIcon(Icons.description_outlined), findsNothing);
  });

  testWidgets('a text-only model gets an attach button that opens the picker '
      'directly', (tester) async {
    var attached = 0;
    await pump(tester, onAttachDocument: () => attached++);
    expect(find.byTooltip('Attach document'), findsOneWidget);
    await tester.tap(find.byTooltip('Attach document'));
    await tester.pump();
    expect(attached, 1);
    expect(find.text('Photo Library'), findsNothing); // no sheet
  });

  testWidgets('a vision model gets a sheet with Photo, Camera and Document', (
    tester,
  ) async {
    var attached = 0;
    await pump(tester, isMultimodal: true, onAttachDocument: () => attached++);
    await tester.tap(find.byTooltip('Attach image or document'));
    await tester.pumpAndSettle();
    expect(find.text('Photo Library'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    await tester.tap(find.text('Document (PDF, TXT, MD)'));
    await tester.pumpAndSettle();
    expect(attached, 1);
    expect(find.text('Photo Library'), findsNothing); // sheet closed
  });

  testWidgets('an attached document shows name, pages and characters', (
    tester,
  ) async {
    await pump(
      tester,
      documents: [doc(7, 'Quarterly report.pdf')],
      onAttachDocument: () {},
    );
    expect(find.text('Quarterly report.pdf'), findsOneWidget);
    expect(find.text('12 pages · 14,498 characters'), findsOneWidget);
  });

  testWidgets('a text file shows characters only, singular page handled', (
    tester,
  ) async {
    await pump(
      tester,
      documents: [
        doc(1, 'notes.txt', pages: 0, chars: 3200),
        doc(2, 'one.pdf', pages: 1, chars: 900),
      ],
      onAttachDocument: () {},
    );
    expect(find.text('3,200 characters'), findsOneWidget);
    expect(find.text('1 page · 900 characters'), findsOneWidget);
  });

  testWidgets('the remove button is a 48dp target and removes that document', (
    tester,
  ) async {
    final removed = <int>[];
    await pump(
      tester,
      documents: [doc(7, 'a.pdf'), doc(8, 'b.pdf')],
      onAttachDocument: () {},
      onRemoveDocument: removed.add,
    );
    final remove = find.byTooltip('Remove b.pdf');
    expect(remove, findsOneWidget);
    final size = tester.getSize(remove);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(remove);
    expect(removed, [8]);
  });

  testWidgets('while reading, a progress chip shows and attach is disabled', (
    tester,
  ) async {
    await pump(tester, extractingDocName: 'big.pdf', onAttachDocument: () {});
    expect(find.text('big.pdf'), findsOneWidget);
    expect(find.text('Reading document…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.description_outlined),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the Reading chip has a Cancel', (tester) async {
    var cancelled = 0;
    await pump(
      tester,
      extractingDocName: 'big.pdf',
      onAttachDocument: () {},
      onCancelDocumentRead: () => cancelled++,
    );
    final cancel = find.byTooltip('Cancel reading big.pdf');
    expect(cancel, findsOneWidget);
    final size = tester.getSize(cancel);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(cancel);
    expect(cancelled, 1);
  });

  testWidgets('an extraction error is shown in plain words and dismissible', (
    tester,
  ) async {
    var dismissed = 0;
    await pump(
      tester,
      documentError: 'This PDF has no selectable text.',
      onAttachDocument: () {},
      onDismissDocumentError: () => dismissed++,
    );
    expect(find.text('This PDF has no selectable text.'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    expect(dismissed, 1);
  });

  testWidgets('chips expose a semantic label with name and size', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      documents: [doc(7, 'Quarterly report.pdf')],
      onAttachDocument: () {},
    );
    expect(
      find.bySemanticsLabel(
        'Attached document Quarterly report.pdf, 12 pages · 14,498 characters',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('long names ellipsize instead of overflowing', (tester) async {
    await pump(
      tester,
      documents: [doc(1, '${'very-long-file-name-' * 12}.pdf')],
      onAttachDocument: () {},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion: chips appear without a size animation', (
    tester,
  ) async {
    await pump(
      tester,
      documents: [doc(1, 'a.pdf')],
      onAttachDocument: () {},
      disableAnimations: true,
    );
    expect(find.text('a.pdf'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
