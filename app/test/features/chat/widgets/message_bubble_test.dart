import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/features/chat/state/message_info_x.dart';
import 'package:dhruva/features/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

MessageInfo _message({
  required MessageRole role,
  required String content,
  String? reasoningContent,
  MessageStatus status = MessageStatus.complete,
}) {
  return MessageInfo(
    id: 1,
    conversationId: 1,
    role: role,
    content: content,
    reasoningContent: reasoningContent,
    status: status,
    createdAt: DateTime.now(),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  // The copy-button test exercises `Clipboard.setData`, which has no
  // built-in mock in `flutter_test` (it's a real engine channel call) —
  // stub it so the async gap resolves instead of throwing.
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

  testWidgets('user message renders its text', (tester) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(role: MessageRole.user, content: 'hello there'),
      ),
    );
    expect(find.textContaining('hello there'), findsOneWidget);
  });

  testWidgets('system message renders as a centered italic banner', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(role: MessageRole.system, content: 'Model changed'),
      ),
    );
    expect(find.text('Model changed'), findsOneWidget);
  });

  testWidgets(
    'assistant markdown renders bold text and a code block with copy',
    (tester) async {
      await _pump(
        tester,
        MessageBubble(
          message: _message(
            role: MessageRole.assistant,
            content: '**bold** text\n\n```dart\nprint(1);\n```',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('bold'), findsOneWidget);
      expect(find.text('dart'), findsOneWidget); // language label
      expect(find.byIcon(Icons.copy), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);
      // Let the copy-icon's revert timer (motion.moderate, 300ms) run out so
      // no pending timer trips flutter_test's end-of-test invariant check.
      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  testWidgets('reasoning block is collapsed by default and expands on tap', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(
          role: MessageRole.assistant,
          content: 'the answer',
          reasoningContent: 'the scratch work',
        ),
        reasoningDurationMs: 4200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reasoning (4s)'), findsOneWidget);
    expect(find.text('the scratch work'), findsNothing);

    await tester.tap(find.text('Reasoning (4s)'));
    await tester.pumpAndSettle();

    expect(find.text('the scratch work'), findsOneWidget);
  });

  testWidgets('an actively streaming reasoning block reads "Reasoning…"', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(
          role: MessageRole.assistant,
          content: '',
          reasoningContent: 'still going',
        ),
        isStreaming: true,
        reasoningOpen: true,
      ),
    );

    expect(find.text('Reasoning…'), findsOneWidget);
  });

  testWidgets('regenerate/edit affordances fire their callbacks', (
    tester,
  ) async {
    var regenerated = false;
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              MessageBubble(
                message: _message(role: MessageRole.assistant, content: 'hi'),
                onRegenerate: () => regenerated = true,
              ),
              MessageBubble(
                message: _message(role: MessageRole.user, content: 'question'),
                onEdit: () => edited = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.refresh));
    expect(regenerated, isTrue);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    expect(edited, isTrue);
  });
}
