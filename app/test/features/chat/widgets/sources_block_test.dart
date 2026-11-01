import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/docs/grounding.dart';
import 'package:dhruva/features/chat/widgets/sources_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sources = [
  DocSource(
    docName: 'terms.pdf',
    page: 2,
    paged: true,
    snippet: 'The warranty lasts two years.',
  ),
  DocSource(
    docName: 'terms.pdf',
    page: 4,
    paged: true,
    snippet: 'Claims need the original receipt.',
  ),
];

Future<void> pump(WidgetTester tester, List<DocSource> sources) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SourcesBlock(sources: sources)),
    ),
  );
}

void main() {
  testWidgets('collapsed by default: header lists the pages, no snippets', (
    tester,
  ) async {
    await pump(tester, _sources);
    expect(find.text('Sources · p.2, p.4'), findsOneWidget);
    expect(find.text('The warranty lasts two years.'), findsNothing);
  });

  testWidgets('tapping expands to page chips with snippets, tapping again '
      'collapses', (tester) async {
    await pump(tester, _sources);
    await tester.tap(find.text('Sources · p.2, p.4'));
    await tester.pumpAndSettle();
    expect(find.text('The warranty lasts two years.'), findsOneWidget);
    expect(find.text('Claims need the original receipt.'), findsOneWidget);
    expect(find.text('p.2'), findsOneWidget);
    // One document: the file name is not repeated per row.
    expect(find.text('terms.pdf'), findsNothing);

    await tester.tap(find.text('Sources · p.2, p.4'));
    await tester.pumpAndSettle();
    expect(find.text('The warranty lasts two years.'), findsNothing);
  });

  testWidgets('several documents: each row names its file', (tester) async {
    await pump(tester, const [
      DocSource(docName: 'a.pdf', page: 1, paged: true, snippet: 's1'),
      DocSource(docName: 'n.txt', page: 2, paged: false, snippet: 's2'),
    ]);
    await tester.tap(find.textContaining('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('n.txt'), findsOneWidget);
    expect(find.text('part 2'), findsWidgets); // plain text uses "part N"
  });

  testWidgets('the header is a 48dp target with a semantic label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, _sources);
    expect(find.bySemanticsLabel('Sources: p.2, p.4'), findsOneWidget);
    final size = tester.getSize(find.byType(InkWell).first);
    expect(size.height, greaterThanOrEqualTo(48));
    handle.dispose();
  });
}
