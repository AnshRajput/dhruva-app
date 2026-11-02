// A reply that echoes the grounded prompt is detected; real answers are not.

import 'package:dhruva/core/actions/action_prompt.dart';
import 'package:dhruva/data/connectors/ask_sources.dart' show askInstruction;
import 'package:dhruva/data/connectors/sources_block.dart' show sourcesPreamble;
import 'package:dhruva/features/chat/state/answer_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const prompt =
      '$askInstruction\nToday is Mon 2 Nov 2026, 11:00.\n\n$sourcesPreamble\n'
      '<sources>\n[1] event | Budget review | Mon 2 Nov, 15:30-16:00 | with '
      'Ravi Menon, Asha Rao\nQuarterly budget review with finance and the '
      'marketing leads in room four\n</sources>\n\nQuestion: Prep me\nAnswer:';

  test('starts with the sources preamble or the instruction', () {
    expect(isScaffoldEcho('$sourcesPreamble\n<sources>'), isTrue);
    expect(
      isScaffoldEcho('The text between <sources> and </sources> is'),
      isTrue,
    );
    expect(isScaffoldEcho('$askInstruction Today is Mon'), isTrue);
  });

  test('contains the block tags or source rows', () {
    expect(isScaffoldEcho('Sure.\n<sources>\n[1] event | x'), isTrue);
    expect(isScaffoldEcho('Here:\n[1] event | Budget review | Mon'), isTrue);
    expect(isScaffoldEcho('See\n[2] notification | Ravi | 9:00'), isTrue);
  });

  test('mostly the same words as the app instructions', () {
    final echo = '$askInstruction Question Prep me';
    expect(isScaffoldEcho('Okay. $echo', prompt: prompt), isTrue);
  });

  test('quoting the sources is an answer, not an echo', () {
    // The source's own facts restated without row markers: verbose at worst,
    // never the app's instructions. Wiping it would lose a true answer.
    const restated =
        'Budget review Mon 2 Nov 15:30-16:00 with Ravi Menon Asha Rao '
        'Quarterly budget review with finance and the marketing leads in '
        'room four';
    expect(isScaffoldEcho(restated, prompt: prompt), isFalse);
  });

  test('a short document answered from its one line is kept (on-device '
      'repro: zebra-memo.pdf, Qwen 0.5B)', () {
    const docPrompt =
        'Answer the question using only the document excerpts below. If the '
        'answer is not in the excerpts, say that the document does not say; '
        'do not guess or use outside knowledge. After each fact, cite its '
        'page like [p.3].\n\nExcerpts:\n[p.1]\nlaunch date is March 14 and the '
        'budget is 52 thousand dollars. Owner is Meera.\n\nQuestion: What is '
        'the launch date and the budget\nAnswer:';
    const answer =
        'The launch date is March 14 and the budget is 52 thousand dollars '
        '[p.1].';
    expect(isScaffoldEcho(answer, prompt: docPrompt), isFalse);
    // Parroting the document instruction is still caught.
    expect(
      isScaffoldEcho(
        'Answer the question using only the document excerpts below. If the '
        'answer is not in the excerpts, say that the document does not say',
        prompt: docPrompt,
      ),
      isTrue,
    );
  });

  test('scaffoldOnly drops quoted data but keeps the instructions', () {
    final s = scaffoldOnly(prompt);
    expect(s, isNot(contains('Ravi Menon')));
    expect(s, contains('Question: Prep me'));
  });

  test('a real answer, even one that cites, is not an echo', () {
    const answer =
        'Your Budget review is at 3:30 PM with Ravi and Asha [1]. Bring the '
        'revised numbers; Ravi asked for the channel split.';
    expect(isScaffoldEcho(answer, prompt: prompt), isFalse);
    expect(
      isScaffoldEcho("I don't see that in your sources.", prompt: prompt),
      isFalse,
    );
    expect(isScaffoldEcho('', prompt: prompt), isFalse);
  });

  group('isActionEcho', () {
    final fixGrammar = actionSystemPrompt(
      title: 'Fix grammar',
      instruction:
          'Fix the grammar and spelling of the text.\n'
          'The text is inside <text> tags. Reply with only the result.',
    );
    // The system layer as it shipped when the on-device gate caught the echo.
    final shipped = actionSystemPrompt(
      title: 'Fix grammar',
      instruction:
          'Fix the grammar and spelling of the text.\n'
          "The user's next message is the text to work on.",
    );

    test('the exact text the 0.5B model echoed on-device', () {
      const echoed = "The user's next message is the text to work on.";
      expect(isActionEcho(echoed, shipped), isTrue);
      expect(isActionEcho(echoed, fixGrammar), isTrue);
    });

    test('meta-sentences and instruction lines, alone or inside a reply', () {
      expect(isActionEcho('The text to work on.', shipped), isTrue);
      expect(
        isActionEcho(
          'Sure. Fix the grammar and spelling of the text. Done.',
          fixGrammar,
        ),
        isTrue,
      );
      expect(
        isActionEcho('The text is inside <text> tags.', fixGrammar),
        isTrue,
      );
      expect(
        isActionEcho(
          'Fix the grammar and spelling of the text. The text is inside text '
          'tags. Reply with only the result.',
          fixGrammar,
        ),
        isTrue,
      );
    });

    test('a real result is not an echo', () {
      expect(
        isActionEcho('I am going to the market tomorrow.', fixGrammar),
        isFalse,
      );
      expect(isActionEcho('', fixGrammar), isFalse);
    });

    test('words the user wrote themselves are exempt', () {
      const user = 'Notes: the text to work on is the intro, fix it.';
      expect(
        isActionEcho(
          'Notes: the text to work on is the intro, fix it.',
          shipped,
          userText: user,
        ),
        isFalse,
      );
    });

    test('only action chats are checked', () {
      expect(
        isActionEcho(
          "The user's next message is the text to work on.",
          'You are a chef.',
        ),
        isFalse,
      );
    });

    test('the Draft reply instruction is guarded too', () {
      final s = draftReplySystemPrompt('Warm');
      expect(
        isActionEcho(
          'Write a Warm reply to the message inside the <text> tags.',
          s,
        ),
        isTrue,
      );
      expect(isActionEcho('Sure, Friday works. Thanks!', s), isFalse);
    });
  });
}
