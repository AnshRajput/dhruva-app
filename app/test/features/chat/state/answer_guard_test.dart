// A reply that echoes the grounded prompt is detected; real answers are not.

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

  test('mostly the same words as the sources block', () {
    const dump =
        'Budget review Mon 2 Nov 15:30-16:00 with Ravi Menon Asha Rao '
        'Quarterly budget review with finance and the marketing leads in '
        'room four';
    expect(isScaffoldEcho(dump, prompt: prompt), isTrue);
    expect(
      isScaffoldEcho(dump),
      isFalse,
      reason: 'needs the prompt to compare',
    );
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
}
