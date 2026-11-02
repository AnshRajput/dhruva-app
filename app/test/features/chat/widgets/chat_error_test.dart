import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/chat/widgets/chat_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('errorKind mapping covers the full chat-spec.md §8 taxonomy', () {
    // D2: every load failure leads with Try again, then Use a smaller model.
    for (final kind in [
      'EngineOutOfMemoryFailure',
      'EngineLoadTimeoutFailure',
      'EngineLoadFailure',
    ]) {
      final c = chatErrorContentFor(kind);
      expect(c.primaryAction, ChatRecoveryAction.retry, reason: kind);
      expect(c.primaryLabel, 'Try again', reason: kind);
      expect(c.secondaryAction, ChatRecoveryAction.smallerModel, reason: kind);
      expect(c.secondaryLabel, 'Use a smaller model', reason: kind);
    }
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

  test('D2: corrupt file, memory and timeout read differently', () {
    final corrupt = chatErrorContentFor('EngineLoadFailure').message;
    final memory = chatErrorContentFor('EngineOutOfMemoryFailure').message;
    final timeout = chatErrorContentFor('EngineLoadTimeoutFailure').message;
    expect({corrupt, memory, timeout}, hasLength(3));
    expect(corrupt, contains('damaged'));
    expect(memory, contains('memory'));
    expect(timeout, contains('too long'));
    // Only the corrupt-file case offers Re-download, last, with the real size.
    final c = chatErrorContentFor(
      'EngineLoadFailure',
      modelSizeBytes: 379 * 1024 * 1024,
    );
    expect(c.tertiaryAction, ChatRecoveryAction.redownload);
    expect(c.tertiaryLabel, 'Re-download (379 MB)');
    expect(
      chatErrorContentFor('EngineOutOfMemoryFailure').tertiaryAction,
      isNull,
    );
    expect(
      chatErrorContentFor('EngineLoadTimeoutFailure').tertiaryAction,
      isNull,
    );
    expect(
      chatErrorContentFor(
        'EngineLoadFailure',
        modelSizeBytes: 2 * 1024 * 1024 * 1024,
      ).tertiaryLabel,
      'Re-download (2.0 GB)',
    );
  });

  testWidgets('ChatErrorCard shows all three recoveries in order and fires '
      'the tapped one', (tester) async {
    ChatRecoveryAction? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ChatErrorCard(
            content: chatErrorContentFor(
              'EngineLoadFailure',
              modelSizeBytes: 379 * 1024 * 1024,
            ),
            onAction: (action) => tapped = action,
          ),
        ),
      ),
    );

    expect(find.textContaining("file couldn't be read"), findsOneWidget);
    final tryAgain = tester.getTopLeft(find.text('Try again'));
    final smaller = tester.getTopLeft(find.text('Use a smaller model'));
    final redownload = tester.getTopLeft(find.text('Re-download (379 MB)'));
    // Re-download is last (reading order: same row then wrapped).
    expect(
      tryAgain.dy < redownload.dy ||
          (tryAgain.dy == redownload.dy &&
              tryAgain.dx < smaller.dx &&
              smaller.dx < redownload.dx),
      isTrue,
    );

    await tester.tap(find.text('Re-download (379 MB)'));
    expect(tapped, ChatRecoveryAction.redownload);
    await tester.tap(find.text('Use a smaller model'));
    expect(tapped, ChatRecoveryAction.smallerModel);
    await tester.tap(find.text('Try again'));
    expect(tapped, ChatRecoveryAction.retry);
  });

  test('a busy model names its cause', () {
    String say(String? d) =>
        chatErrorContentFor('EngineStateFailure', detail: d).message;
    expect(say('a speed test is running'), contains('speed test'));
    expect(say('a generation is already in flight'), contains('another task'));
    expect(say('a generation is already in flight'), isNot(contains('speed')));
    expect(say('model is loading'), contains('still loading'));
    expect(say(null), 'The model is busy for a moment. Try again.');
    expect(say(''), isNot(contains('speed')));
  });
}
