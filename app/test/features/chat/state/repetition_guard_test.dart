import 'package:dhruva/features/chat/state/repetition_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const real =
      '[1]. Ana Costa is an individual with a valid contact phone number '
      'provided by Ana Costa, Ana Costa, with Ana Costa, with Ana Costa.';

  test('the real looped Ask answer is degenerate', () {
    expect(isDegenerateReply(real), isTrue);
  });

  test('a four-word run repeated three times is a loop', () {
    expect(hasRepeatLoop('the cat sat down ' * 3), isTrue);
  });

  test('a normal answer that names a person twice is not degenerate', () {
    const ok =
        'Ana Costa has a design review on Monday at ten, and Ana Costa also '
        'asked you to bring the Q4 budget. Ravi will join from the Pune '
        'office, so book the small room and send him the dial-in link.';
    expect(isDegenerateReply(ok), isFalse);
    expect(hasRepeatLoop(ok), isFalse);
  });

  test('a short reply is never degenerate', () {
    expect(isDegenerateReply('Ana Costa, Ana Costa, Ana Costa.'), isFalse);
  });
}
