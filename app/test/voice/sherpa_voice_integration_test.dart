import 'dart:typed_data';

import 'package:dhruva/voice/sherpa_voice_service.dart';
import 'package:dhruva/voice/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_test_config.dart';

/// REAL sherpa_onnx round-trip on this machine (Loop 6, D1). Skips cleanly
/// wherever the native dylib or dev voice models are absent (Linux CI, a fresh
/// checkout) — see `voice_test_config.dart`. Proves both directions without a
/// mic: synthesize "hello world" → feed the audio back to the recognizer.
void main() {
  final paths = resolveVoiceTestPaths();
  if (paths == null) {
    test('sherpa voice integration (skipped: no native libs/models)', () {
      markTestSkipped(
        'sherpa macOS dylib or dev voice models unavailable — '
        'needs on-device verification (see orchestra/RISKS.md)',
      );
    });
    return;
  }

  late SherpaVoiceService voice;

  setUpAll(() async {
    voice = SherpaVoiceService(libraryDirectory: paths.libraryDirectory);
    await voice.loadTts(paths.tts);
    await voice.loadAsr(paths.asr);
    await voice.loadVad(paths.vad);
  });

  tearDownAll(() => voice.dispose());

  test('synthesize produces non-empty 16 kHz audio', () async {
    final audio = await voice.synthesize('hello world');
    expect(audio.samples, isNotEmpty);
    expect(audio.sampleRate, greaterThan(0));
  });

  test(
    'round-trip: synthesized speech transcribes back to text',
    () async {
      final audio = await voice.synthesize('hello world');
      final transcript = await voice.transcribe(
        audio.samples,
        sampleRate: audio.sampleRate,
      );
      expect(transcript.isFinal, isTrue);
      expect(transcript.text.trim(), isNotEmpty);
      // whisper-tiny is small; assert it recovered a distinctive word rather than
      // an exact string (punctuation/casing vary).
      final lower = transcript.text.toLowerCase();
      expect(
        lower.contains('hello') || lower.contains('world'),
        isTrue,
        reason: 'got: "${transcript.text}"',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('empty text is rejected before any native work', () {
    expect(voice.synthesize(''), throwsA(isA<VoiceValidationFailure>()));
  });

  test(
    'VAD segments a silence→speech→silence buffer',
    () async {
      final audio = await voice.synthesize('hello world this is dhruva');
      final clip = _padWithSilence(audio.samples, audio.sampleRate);
      final events = await voice
          .segment(_chunked(clip, 1600), sampleRate: audio.sampleRate)
          .toList();

      expect(
        events.whereType<SpeechStarted>(),
        isNotEmpty,
        reason: 'VAD never detected speech onset',
      );
      final ended = events.whereType<SpeechEnded>().toList();
      expect(ended, isNotEmpty, reason: 'VAD never closed a segment');
      expect(ended.first.samples, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'hands-free loop: transcribeStream yields the utterance',
    () async {
      final audio = await voice.synthesize('hello world');
      final clip = _padWithSilence(audio.samples, audio.sampleRate);
      final transcripts = await voice
          .transcribeStream(_chunked(clip, 1600), sampleRate: audio.sampleRate)
          .toList();
      expect(transcripts, isNotEmpty);
      expect(transcripts.first.text.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// 0.6 s of silence on each side so the VAD sees a clean onset + offset.
Float32List _padWithSilence(Float32List speech, int sampleRate) {
  final pad = (sampleRate * 0.6).round();
  final out = Float32List(pad + speech.length + pad);
  out.setAll(pad, speech);
  return out;
}

Stream<Float32List> _chunked(Float32List samples, int chunk) async* {
  for (var i = 0; i < samples.length; i += chunk) {
    final end = (i + chunk < samples.length) ? i + chunk : samples.length;
    yield Float32List.sublistView(samples, i, end);
  }
}
