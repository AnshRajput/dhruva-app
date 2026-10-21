import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/workflows/data/workflow_catalog.dart';
import 'package:dhruva/features/workflows/ui/workflows_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<GoRouter> pump(WidgetTester tester, {String? text}) async {
    final router = GoRouter(
      initialLocation: '/workflows',
      routes: [
        GoRoute(
          path: '/workflows',
          builder: (_, _) => WorkflowsScreen(initialText: text),
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (_, s) => Scaffold(body: Text('chat ${s.uri.query}')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Run is disabled until there is input, then pushes the prompt', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Runs on your phone. Nothing is uploaded.'), findsOne);

    await tester.tap(find.text('Translate'));
    await tester.pumpAndSettle();

    final run = find.widgetWithText(FilledButton, 'Run');
    expect(tester.widget<FilledButton>(run).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'good morning');
    await tester.tap(find.text('Hindi'));
    await tester.pump();
    expect(tester.widget<FilledButton>(run).onPressed, isNotNull);

    await tester.tap(run);
    await tester.pumpAndSettle();

    final workflow = workflowCatalog.firstWhere((w) => w.id == 'translate');
    final rendered = renderWorkflowPrompt(workflow, 'good morning', 'Hindi');
    expect(find.text('chat prompt=${Uri.encodeComponent(rendered)}'), findsOne);
  });

  testWidgets('shared text prefills the sheet', (tester) async {
    await pump(tester, text: 'shared words');
    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'shared words',
    );
  });

  testWidgets('over-long prefill is trimmed with a note', (tester) async {
    await pump(tester, text: 'x' * (workflowInputLimit + 10));
    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trimmed to'), findsOne);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      workflowInputLimit,
    );
  });
}
