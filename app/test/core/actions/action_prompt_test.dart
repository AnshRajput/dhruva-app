import 'package:dhruva/core/actions/action_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the system prompt carries a title header the thread can read back', () {
    final s = actionSystemPrompt(
      title: 'Translate',
      instruction: 'Translate into Hindi.',
    );
    expect(s, 'Action: Translate\nTranslate into Hindi.');
    expect(actionTitleOf(s), 'Translate');
    expect(actionTitleOf('You are a chef.'), isNull);
    expect(actionTitleOf('Action: '), isNull);
    expect(isDraftReplyChat(s), isFalse);
  });

  test('draft chats know their tone', () {
    for (final t in draftTones) {
      final s = draftReplySystemPrompt(t);
      expect(isDraftReplyChat(s), isTrue);
      expect(draftToneOf(s), t);
    }
    expect(draftToneOf('Action: Draft a reply\nsomething else'), 'Warm');
  });

  group('omissions', () {
    const source =
        'Hi Meera, can you approve the budget by Friday? Also please review '
        'the vendor contract. Thanks, Marcus';

    test('names what the draft left out', () {
      const draft =
          'Hi Marcus, I approved the budget and will confirm by Friday.\n'
          'Best regards, Meera';
      expect(draftOmissions(source, draft), ['review the vendor contract']);
      expect(
        omissionNote(source, draft),
        "Didn't cover: review the vendor contract",
      );
    });

    test('nothing to report when every ask is answered', () {
      const draft =
          'Approved the budget for Friday. I will review the vendor contract '
          'today.';
      expect(draftOmissions(source, draft), isEmpty);
      expect(omissionNote(source, draft), isNull);
    });

    test('the Inbox "Sender: body" pre-fill drops the sender', () {
      const inbox =
          'Ravi Menon: Can you approve the 18.4L marketing line by EOD? '
          'Also send the signed invoice.';
      expect(draftOmissions(inbox, 'Ok'), [
        'approve the 18.4L marketing line by EOD',
        'send the signed invoice',
      ]);
      expect(
        omissionNote(inbox, 'Approved the marketing line.'),
        "Didn't cover: send the signed invoice",
      );
    });

    test('statements are not asks, and the list is capped', () {
      expect(draftOmissions('Reached home. Dinner was great.', 'Ok'), isEmpty);
      const many =
          'Can you book the venue? Can you order the cake? Can you invite '
          'the neighbours? Can you print the posters?';
      expect(draftOmissions(many, 'Sure, thanks'), hasLength(3));
    });
  });
}
