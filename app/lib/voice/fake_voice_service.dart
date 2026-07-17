/// An in-memory [VoiceService] with no native code, for unit/widget tests
/// (mirrors `FakeEngineService`).
///
/// It faithfully models the parts of the contract that matter for orchestration
/// tests: scripted transcription + synthesis, typed failure surfacing, and — the
/// important one — a deterministic energy-based VAD so turn-taking and barge-in
/// logic can be exercised without a mic or native libs. Feed silence (zeros) and
/// speech (non-zero) chunks; [segment] emits [SpeechStarted] on the rising edge
/// and [SpeechEnded] with the accumulated speech samples on the falling edge.
library;

import 'dart:typed_data';

import 'voice_service.dart';

final class FakeVoiceService implements VoiceService {
  /// Text every [transcribe] returns (unless a segment carries [_echoTag]).
  final String scriptedTranscript;
  final String? scriptedLanguage;

  /// Samples every [synthesize] returns. Defaults to 0.25 s of 16 kHz audio.
  final Float32List synthSamples;
  final int synthSampleRate;

  /// Above this max-abs sample amplitude, a chunk counts as speech.
  final double vadThreshold;

  final VoiceFailure? asrLoadFailure;
  final VoiceFailure? ttsLoadFailure;
  final VoiceFailure? vadLoadFailure;
  final VoiceFailure? transcribeFailure;
  final VoiceFailure? synthesizeFailure;

  FakeVoiceService({
    this.scriptedTranscript = 'hello world',
    this.scriptedLanguage = 'en',
    Float32List? synthSamples,
    this.synthSampleRate = 16000,
    this.vadThreshold = 0.01,
    this.asrLoadFailure,
    this.ttsLoadFailure,
    this.vadLoadFailure,
    this.transcribeFailure,
    this.synthesizeFailure,
  }) : synthSamples = synthSamples ?? Float32List(4000);

  bool _asrReady = false;
  bool _ttsReady = false;
  bool _vadReady = false;
  bool _disposed = false;

  /// Test hooks.
  int transcribeCount = 0;
  int synthesizeCount = 0;
  int cancelCount = 0;
  String? lastSynthesizedText;

  @override
  bool get isAsrReady => _asrReady && !_disposed;
  @override
  bool get isTtsReady => _ttsReady && !_disposed;
  @override
  bool get isVadReady => _vadReady && !_disposed;

  @override
  Future<void> loadAsr(AsrModelConfig config) async {
    _throwIfDisposed();
    if (asrLoadFailure != null) throw asrLoadFailure!;
    _asrReady = true;
  }

  @override
  Future<void> loadTts(TtsModelConfig config) async {
    _throwIfDisposed();
    if (ttsLoadFailure != null) throw ttsLoadFailure!;
    _ttsReady = true;
  }

  @override
  Future<void> loadVad(VadConfig config) async {
    _throwIfDisposed();
    if (vadLoadFailure != null) throw vadLoadFailure!;
    _vadReady = true;
  }

  @override
  Future<Transcript> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    if (!isAsrReady) {
      throw const VoiceDisposedFailure('no ASR model loaded; call loadAsr()');
    }
    if (transcribeFailure != null) throw transcribeFailure!;
    transcribeCount++;
    // Empty/near-silent input → empty transcript (models return nothing).
    final text = _hasSpeech(samples) ? scriptedTranscript : '';
    return Transcript(text, language: text.isEmpty ? null : scriptedLanguage);
  }

  @override
  Stream<Transcript> transcribeStream(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
  }) async* {
    await for (final event in segment(audio, sampleRate: sampleRate)) {
      if (event is SpeechEnded) {
        final t = await transcribe(event.samples, sampleRate: sampleRate);
        if (t.text.trim().isNotEmpty) yield t;
      }
    }
  }

  @override
  Future<SynthesizedAudio> synthesize(
    String text, {
    int voiceId = 0,
    double speed = 1.0,
  }) async {
    final invalid = checkSynthesizeArgs(text);
    if (invalid != null) throw invalid;
    if (!isTtsReady) {
      throw const VoiceDisposedFailure('no TTS voice loaded; call loadTts()');
    }
    if (synthesizeFailure != null) throw synthesizeFailure!;
    synthesizeCount++;
    lastSynthesizedText = text;
    return SynthesizedAudio(synthSamples, synthSampleRate);
  }

  @override
  Stream<VadEvent> segment(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
  }) async* {
    if (!isVadReady) {
      throw const VoiceDisposedFailure('no VAD model loaded; call loadVad()');
    }
    var speaking = false;
    var startSample = 0;
    var pos = 0;
    final buffer = <double>[];
    await for (final chunk in audio) {
      if (_hasSpeech(chunk)) {
        if (!speaking) {
          speaking = true;
          startSample = pos;
          buffer.clear();
          yield SpeechStarted(pos * 1000 ~/ sampleRate);
        }
        buffer.addAll(chunk);
      } else if (speaking) {
        speaking = false;
        yield _endSegment(buffer, startSample, sampleRate);
        buffer.clear();
      }
      pos += chunk.length;
    }
    if (speaking) {
      yield _endSegment(buffer, startSample, sampleRate);
    }
  }

  SpeechEnded _endSegment(
    List<double> buffer,
    int startSample,
    int sampleRate,
  ) {
    final samples = Float32List.fromList(buffer);
    return SpeechEnded(
      samples,
      startSample * 1000 ~/ sampleRate,
      samples.length * 1000 ~/ sampleRate,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  bool _hasSpeech(Float32List samples) {
    for (final s in samples) {
      if (s.abs() > vadThreshold) return true;
    }
    return false;
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw const VoiceDisposedFailure('voice service has been disposed');
    }
  }
}
