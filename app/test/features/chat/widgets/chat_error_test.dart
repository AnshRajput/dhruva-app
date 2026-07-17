import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/chat/widgets/chat_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('errorKind mapping covers the full chat-spec.md §8 taxonomy', () {
    expect(
      chatErrorContentFor('EngineOutOfMemoryFailure').primaryAction,
      ChatRecoveryAction.smallerModel,
    );
    expect(
      chatErrorContentFor('EngineOutOfMemoryFailure').secondaryAction,
      ChatRecoveryAction.retryAnyway,
    );
    expect(
      chatErrorContentFor('EngineLoadFailure').primaryAction,
      ChatRecoveryAction.redownload,
    );
    expect(
      chatErrorContentFor('EngineDisposedFailure').primaryAction,
      ChatRecoveryAction.reloadModel,
    );
    expect(
      chatErrorContentFor('EngineDecodeFailure').primaryAction,
      ChatRecoveryAction.retry,
    );
    expect(
      chatErrorContentFor('EngineStateFailure').primaryAction,
      ChatRecoveryAction.retry,
    );
    expect(
      chatErrorContentFor('EngineValidationFailure').primaryAction,
      ChatRecoveryAction.retry,
    );
    final unknown = chatErrorContentFor('EngineUnknownFailure');
    expect(unknown.primaryAction, ChatRecoveryAction.retry);
    expect(unknown.secondaryAction, ChatRecoveryAction.copyDetails);
    // A never-before-seen errorKind string falls back to the same generic copy.
    expect(chatErrorContentFor(null).primaryAction, ChatRecoveryAction.retry);
    expect(
      chatErrorContentFor('SomethingNew').secondaryAction,
      ChatRecoveryAction.copyDetails,
    );
  });

  testWidgets('ChatErrorCard renders the message and fires the tapped action', (
    tester,
  ) async {
    ChatRecoveryAction? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ChatErrorCard(
            content: chatErrorContentFor('EngineOutOfMemoryFailure'),
            onAction: (action) => tapped = action,
          ),
        ),
      ),
    );

    expect(
      find.text(
        'This model needs more memory than your device has free right now.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try a smaller model'), findsOneWidget);
    expect(find.text('Retry anyway'), findsOneWidget);

    await tester.tap(find.text('Retry anyway'));
    expect(tapped, ChatRecoveryAction.retryAnyway);

    await tester.tap(find.text('Try a smaller model'));
    expect(tapped, ChatRecoveryAction.smallerModel);
  });
}
