import 'package:dhruva/features/voice/state/default_voice.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
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

  group('installed-aware fallback', () {
    bool onlyEnglish(VoiceCatalogEntry e) => e.id == 'piper-en-amy-low';
    bool onlyHindi(VoiceCatalogEntry e) => e.id == 'piper-hi-pratham-medium';
    bool none(VoiceCatalogEntry e) => false;

    test('Hindi reply falls back to the installed English voice (the one-tap '
        'bundle only ships English) instead of a silent, text-only turn', () {
      final entry = defaultVoiceEntryFor('नमस्ते', isInstalled: onlyEnglish);
      expect(entry?.id, 'piper-en-amy-low');
    });

    test('English reply falls back to the installed Hindi voice', () {
      final entry = defaultVoiceEntryFor('Hello', isInstalled: onlyHindi);
      expect(entry?.id, 'piper-hi-pratham-medium');
    });

    test('language-matched voice still wins when it is installed', () {
      final entry = defaultVoiceEntryFor('नमस्ते', isInstalled: (e) => true);
      expect(entry?.id, 'piper-hi-pratham-medium');
    });

    test('null only when no TTS voice is installed at all', () {
      expect(defaultVoiceEntryFor('Hello', isInstalled: none), isNull);
    });
  });
}
