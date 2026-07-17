/// Abstract on-device voice surface (Loop 6) — the STT + TTS + VAD analogue of
/// `engine_bindings/EngineService`.
///
/// Nothing outside `voice/` imports `sherpa_onnx` or any FFI symbol directly.
/// Features and data depend only on this interface and the neutral types
/// below, so the sherpa_onnx backbone stays swappable and the native crash
/// surface stays contained (same discipline as ADR-001/ADR-002 for the engine).
///
/// Threading: the concrete [SherpaVoiceService] runs every native call — model
/// load, ASR decode, TTS synth, VAD stepping — on a dedicated worker isolate it
/// owns. Whisper decode is the heavy op and must never touch the root isolate.
///
/// VAD is a first-class primitive, not an afterthought (Loop 0 research: the
/// voice differentiator is orchestration — turn-taking + barge-in — not raw
/// STT/TTS). [segment] is the turn-taking source; [transcribeStream] and the
/// hands-free UI (Loop 6 T2) are built on top of it.
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Model configs (engine-neutral; the catalog/installer resolves file paths)
// ---------------------------------------------------------------------------

/// Which sherpa ASR family an [AsrModelConfig] describes. Only `whisper` is
/// wired today (multilingual, covers Hindi/Hinglish). Add a value + a branch in
/// `SherpaVoiceService` when the catalog gains a streaming zipformer.
enum AsrModelType { whisper }

/// Resolved on-disk paths for a non-streaming ASR model.
final class AsrModelConfig {
  final AsrModelType type;
  final String encoder;
  final String decoder;
  final String tokens;

  /// Whisper language hint. Empty string = auto-detect (multilingual), which is
  /// what enables Hindi/Hinglish without the caller knowing the language up
  /// front. A concrete code like `'en'` or `'hi'` pins detection.
  final String language;

  const AsrModelConfig({
    required this.type,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.language = '',
  });
}

/// Which sherpa TTS family a [TtsModelConfig] describes. Only `vits` (Piper) is
/// wired today.
enum TtsModelType { vits }

/// Resolved on-disk paths for a TTS voice.
final class TtsModelConfig {
  final TtsModelType type;
  final String model;
  final String tokens;

  /// espeak-ng-data directory for Piper voices (phonemization). Empty for
  /// models that don't need it.
  final String dataDir;

  const TtsModelConfig({
    required this.type,
    required this.model,
    required this.tokens,
    this.dataDir = '',
  });
}

/// Resolved on-disk path + tuning for the Silero VAD.
final class VadConfig {
  final String model;

  /// Speech probability above which a frame counts as speech (0..1).
  final double threshold;

  /// Silence this long (seconds) ends a segment — the turn-taking timeout.
  final double minSilenceDuration;

  /// Segments shorter than this (seconds) are dropped as noise.
  final double minSpeechDuration;

  const VadConfig({
    required this.model,
    this.threshold = 0.5,
    this.minSilenceDuration = 0.5,
    this.minSpeechDuration = 0.25,
  });
}

// ---------------------------------------------------------------------------
// Results + events
// ---------------------------------------------------------------------------

/// One transcription result. [isFinal] is false for an in-progress guess and
/// true for a settled utterance.
final class Transcript {
  final String text;
  final bool isFinal;

  /// Detected language code when the model reports one (whisper does),
  /// otherwise null. Lets the UI show "heard: Hindi" without a second pass.
  final String? language;

  const Transcript(this.text, {this.isFinal = true, this.language});
}

/// PCM audio produced by [VoiceService.synthesize]: mono float32 samples
/// normalized to [-1, 1] at [sampleRate] Hz.
final class SynthesizedAudio {
  final Float32List samples;
  final int sampleRate;
  const SynthesizedAudio(this.samples, this.sampleRate);
}

/// A turn-taking event from [VoiceService.segment].
sealed class VadEvent {
  const VadEvent();
}

/// The VAD saw speech begin. [startMs] is the offset from the start of the
/// stream. Barge-in listens for this to cancel in-flight TTS.
final class SpeechStarted extends VadEvent {
  final int startMs;
  const SpeechStarted(this.startMs);
}

/// The VAD closed a speech segment (a full utterance). [samples] is the
/// segment's audio (16 kHz mono float32), ready to hand to [VoiceService
/// .transcribe].
final class SpeechEnded extends VadEvent {
  final Float32List samples;
  final int startMs;
  final int durationMs;
  const SpeechEnded(this.samples, this.startMs, this.durationMs);
}

// ---------------------------------------------------------------------------
// Failure taxonomy (the voice branch of the ADR-002 sealed error tree)
// ---------------------------------------------------------------------------

sealed class VoiceFailure implements Exception {
  final String message;
  final Object? cause;
  const VoiceFailure(this.message, {this.cause});
  @override
  String toString() => '$runtimeType: $message';
}

/// A voice model failed to load (bad path, unsupported files, native init).
final class VoiceModelLoadFailure extends VoiceFailure {
  const VoiceModelLoadFailure(super.message, {super.cause});
}

/// ASR decode failed at runtime.
final class VoiceTranscribeFailure extends VoiceFailure {
  const VoiceTranscribeFailure(super.message, {super.cause});
}

/// TTS synthesis failed at runtime.
final class VoiceSynthesizeFailure extends VoiceFailure {
  const VoiceSynthesizeFailure(super.message, {super.cause});
}

/// Bad caller input caught before any native work.
final class VoiceValidationFailure extends VoiceFailure {
  const VoiceValidationFailure(super.message, {super.cause});
}

/// An op was attempted with no model loaded, or after [VoiceService.dispose].
final class VoiceDisposedFailure extends VoiceFailure {
  const VoiceDisposedFailure(super.message, {super.cause});
}

/// Last-resort bucket; always carries the original [cause].
final class VoiceUnknownFailure extends VoiceFailure {
  const VoiceUnknownFailure(super.message, {super.cause});
}

/// Validate a text-to-speech request at the service boundary. Returns the
/// failure to surface, or null if valid. Shared by every implementation so the
/// contract can't drift (mirrors `checkGenerateArgs`).
VoiceFailure? checkSynthesizeArgs(String text) {
  if (text.trim().isEmpty) {
    return const VoiceValidationFailure('text is empty or whitespace-only');
  }
  return null;
}

// ---------------------------------------------------------------------------
// The service
// ---------------------------------------------------------------------------

/// On-device voice: speech-to-text, text-to-speech, and voice-activity
/// segmentation. Models load independently — a caller can run VAD + ASR without
/// TTS, or TTS alone. All methods throw [VoiceFailure] subtypes on error.
abstract interface class VoiceService {
  bool get isAsrReady;
  bool get isTtsReady;
  bool get isVadReady;

  /// Load the ASR model. Replaces any previously loaded ASR model.
  Future<void> loadAsr(AsrModelConfig config);

  /// Load the TTS voice. Replaces any previously loaded voice.
  Future<void> loadTts(TtsModelConfig config);

  /// Load the Silero VAD model. Required before [segment]/[transcribeStream].
  Future<void> loadVad(VadConfig config);

  /// Transcribe a complete utterance (16 kHz mono float32). Throws
  /// [VoiceDisposedFailure] if no ASR model is loaded.
  Future<Transcript> transcribe(Float32List samples, {int sampleRate = 16000});

  /// Segment a live audio stream into utterances using the VAD, transcribing
  /// each closed segment. Emits one final [Transcript] per utterance. (Whisper
  /// is non-streaming, so mid-utterance partials aren't emitted — a streaming
  /// zipformer model would add them; catalog upgrade path.) Requires ASR + VAD.
  Stream<Transcript> transcribeStream(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
  });

  /// Synthesize [text] to audio with the loaded voice. [voiceId] picks a
  /// speaker for multi-speaker models (0 for single-speaker). Throws
  /// [VoiceValidationFailure] on empty text, [VoiceDisposedFailure] if no voice
  /// is loaded.
  Future<SynthesizedAudio> synthesize(
    String text, {
    int voiceId = 0,
    double speed = 1.0,
  });

  /// The turn-taking primitive: run the VAD over [audio] and emit
  /// [SpeechStarted]/[SpeechEnded] events. Requires a loaded VAD. Cancelling the
  /// subscription resets the detector.
  Stream<VadEvent> segment(Stream<Float32List> audio, {int sampleRate = 16000});

  /// Cooperatively stop in-flight work (barge-in). Any running [synthesize] or
  /// [transcribe] result is discarded and the VAD is reset so the next
  /// [segment]/[transcribeStream] starts clean. TTS *playback* is stopped by the
  /// caller's player (main-isolate audio); this stops the *generation* side.
  Future<void> cancel();

  /// Tear down the service (worker isolate + native handles). Unusable after.
  Future<void> dispose();
}
