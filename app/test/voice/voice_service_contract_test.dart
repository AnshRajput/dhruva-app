import 'dart:typed_data';

import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _asr = AsrModelConfig(
  type: AsrModelType.whisper,
  encoder: 'e',
  decoder: 'd',
  tokens: 't',
);
const _tts = TtsModelConfig(type: TtsModelType.vits, model: 'm', tokens: 't');
const _vad = VadConfig(model: 'v');

Float32List _silence(int n) => Float32List(n);
Float32List _speech(int n) =>
    Float32List.fromList(List.generate(n, (i) => i.isEven ? 0.3 : -0.3));

/// Contract every [VoiceService] must honor, verified against the fake. When
/// `SherpaVoiceService` is the subject its real behavior is covered by the
/// gated integration test — this pins the shared, engine-neutral contract.
void main() {
  group('readiness + loading', () {
    test('starts with nothing loaded', () {
      final v = FakeVoiceService();
      expect(v.isAsrReady, isFalse);
      expect(v.isTtsReady, isFalse);
      expect(v.isVadReady, isFalse);
    });

    test('each load flips only its own readiness', () async {
      final v = FakeVoiceService();
      await v.loadAsr(_asr);
      expect(v.isAsrReady, isTrue);
      expect(v.isTtsReady, isFalse);
      await v.loadTts(_tts);
      await v.loadVad(_vad);
      expect(v.isTtsReady, isTrue);
      expect(v.isVadReady, isTrue);
    });

    test('a load failure surfaces as the typed failure', () async {
      final v = FakeVoiceService(
        asrLoadFailure: const VoiceModelLoadFailure('bad asr'),
      );
      await expectLater(v.loadAsr(_asr), throwsA(isA<VoiceModelLoadFailure>()));
      expect(v.isAsrReady, isFalse);
    });
  });

  group('transcribe', () {
    test('throws when no ASR model is loaded', () {
      final v = FakeVoiceService();
      expect(v.transcribe(_speech(1000)), throwsA(isA<VoiceDisposedFailure>()));
    });

    test('speech → transcript with language; silence → empty', () async {
      final v = FakeVoiceService(
        scriptedTranscript: 'namaste',
        scriptedLanguage: 'hi',
      );
      await v.loadAsr(_asr);
      final heard = await v.transcribe(_speech(2000));
      expect(heard.text, 'namaste');
      expect(heard.language, 'hi');
      expect(heard.isFinal, isTrue);
      final quiet = await v.transcribe(_silence(2000));
      expect(quiet.text, isEmpty);
      expect(quiet.language, isNull);
    });

    test('surfaces a decode failure', () async {
      final v = FakeVoiceService(
        transcribeFailure: const VoiceTranscribeFailure('boom'),
      );
      await v.loadAsr(_asr);
      expect(
        v.transcribe(_speech(1000)),
        throwsA(isA<VoiceTranscribeFailure>()),
      );
    });
  });

  group('synthesize', () {
    test('rejects empty text before checking model state', () {
      final v = FakeVoiceService();
      expect(v.synthesize('   '), throwsA(isA<VoiceValidationFailure>()));
    });

    test('throws when no voice is loaded', () {
      final v = FakeVoiceService();
      expect(v.synthesize('hi'), throwsA(isA<VoiceDisposedFailure>()));
    });

    test('returns audio and records the text', () async {
      final v = FakeVoiceService();
      await v.loadTts(_tts);
      final audio = await v.synthesize('hello there');
      expect(audio.samples, isNotEmpty);
      expect(audio.sampleRate, 16000);
      expect(v.lastSynthesizedText, 'hello there');
      expect(v.synthesizeCount, 1);
    });
  });

  group('VAD segmentation (turn-taking)', () {
    test(
      'emits SpeechStarted then SpeechEnded around a speech burst',
      () async {
        final v = FakeVoiceService();
        await v.loadVad(_vad);
        final input = Stream.fromIterable([
          _silence(1600),
          _speech(1600),
          _speech(1600),
          _silence(1600),
        ]);
        final events = await v.segment(input).toList();
        expect(events.whereType<SpeechStarted>(), hasLength(1));
        final ended = events.whereType<SpeechEnded>().toList();
        expect(ended, hasLength(1));
        // Two speech chunks were accumulated into the closed segment.
        expect(ended.single.samples.length, 3200);
        expect(ended.single.durationMs, greaterThan(0));
      },
    );

    test('closes a trailing segment when the stream ends mid-speech', () async {
      final v = FakeVoiceService();
      await v.loadVad(_vad);
      final events = await v
          .segment(Stream.fromIterable([_speech(1600)]))
          .toList();
      expect(events.whereType<SpeechStarted>(), hasLength(1));
      expect(events.whereType<SpeechEnded>(), hasLength(1));
    });

    test('throws when no VAD model is loaded', () {
      final v = FakeVoiceService();
      expect(
        v.segment(const Stream.empty()).toList(),
        throwsA(isA<VoiceDisposedFailure>()),
      );
    });
  });

  group('transcribeStream (segment + transcribe)', () {
    test('yields one transcript per spoken utterance', () async {
      final v = FakeVoiceService(scriptedTranscript: 'ok');
      await v.loadAsr(_asr);
      await v.loadVad(_vad);
      final input = Stream.fromIterable([
        _silence(1600),
        _speech(1600),
        _silence(1600),
        _speech(1600),
        _silence(1600),
      ]);
      final transcripts = await v.transcribeStream(input).toList();
      expect(transcripts, hasLength(2));
      expect(transcripts.every((t) => t.text == 'ok'), isTrue);
    });
  });

  group('cancel + dispose', () {
    test('cancel is a no-throw barge-in signal', () async {
      final v = FakeVoiceService();
      await v.cancel();
      expect(v.cancelCount, 1);
    });

    test('after dispose, loads throw disposed', () async {
      final v = FakeVoiceService();
      await v.dispose();
      expect(v.loadAsr(_asr), throwsA(isA<VoiceDisposedFailure>()));
      expect(v.isAsrReady, isFalse);
    });
  });
}
