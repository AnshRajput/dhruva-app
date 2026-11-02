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

    // The user's own words are the prompt; the instruction rides in the
    // system prompt, never in the user's bubble.
    final workflow = workflowCatalog.firstWhere((w) => w.id == 'translate');
    final expected = workflowChatLocation((
      workflow: workflow,
      text: 'good morning',
      option: 'Hindi',
    ));
    final q = Uri.parse(expected).queryParameters;
    expect(q['prompt'], 'good morning');
    expect(q['asys'], startsWith('Action: Translate\n'));
    expect(q['asys'], contains('Translate the text into Hindi.'));
    expect(q['asys'], isNot(contains('good morning')));
    expect(find.text('chat ${Uri.parse(expected).query}'), findsOne);
  });

  testWidgets('a verb that needs more text says so instead of running', (
    tester,
  ) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Quiz me'), 200);
    await tester.tap(find.text('Quiz me'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Can we move tomorrow standup to 10?',
    );
    await tester.pump();
    final run = find.widgetWithText(FilledButton, 'Run');
    expect(find.byKey(const ValueKey('workflow-too-short')), findsOne);
    expect(tester.widget<FilledButton>(run).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'word ' * 20);
    await tester.pump();
    expect(find.byKey(const ValueKey('workflow-too-short')), findsNothing);
    expect(tester.widget<FilledButton>(run).onPressed, isNotNull);
  });

  testWidgets('Draft a reply carries the source app through to the chat', (
    tester,
  ) async {
    final loc = workflowChatLocation(
      (
        workflow: workflowCatalog.firstWhere((w) => w.id == 'draft_reply'),
        text: 'Ravi: can you approve?',
        option: 'Warm',
      ),
      sourcePackage: 'com.whatsapp',
      sourceApp: 'WhatsApp',
    );
    final q = Uri.parse(loc).queryParameters;
    expect(q['pkg'], 'com.whatsapp');
    expect(q['app'], 'WhatsApp');
    expect(q['asys'], startsWith('Action: Draft a reply\n'));
    expect(q['asys'], contains('Write a Warm reply'));
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
