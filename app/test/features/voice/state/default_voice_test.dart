import 'package:dhruva/features/voice/state/default_voice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English text picks the English voice', () {
    final entry = defaultVoiceEntryFor('Hello, how can I help?');
    expect(entry?.id, 'piper-en-amy-low');
  });

  test('Devanagari text picks the Hindi voice', () {
    final entry = defaultVoiceEntryFor(
      'नमस्ते, मैं आपकी मदद कैसे कर सकता हूँ?',
    );
    expect(entry?.id, 'piper-hi-pratham-medium');
  });

  test('mixed Hinglish-in-Devanagari still routes to Hindi', () {
    final entry = defaultVoiceEntryFor('Hello नमस्ते');
    expect(entry?.id, 'piper-hi-pratham-medium');
  });
}
