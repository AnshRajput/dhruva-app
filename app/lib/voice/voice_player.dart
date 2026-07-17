/// Thin `audioplayers` adapter: play synthesized speech, and — the part that
/// matters for barge-in — [stop] it instantly when the user starts talking.
///
/// Platform glue only (no testable logic, needs a real audio device), so it's
/// excluded from the coverage floor. [SynthesizedAudio] → WAV bytes conversion
/// lives in the pure, tested `floatSamplesToWav`.
///
/// [AudioSink] is the seam Loop 6 T2's TTS button / hands-free controllers
/// depend on instead of this concrete class (same discipline as
/// [MicSource]/[VoiceService]) — widget tests override `audioSinkProvider`
/// with `FakeAudioSink` (`fake_audio_sink.dart`, lib-resident).
library;

import 'package:audioplayers/audioplayers.dart';

import 'audio_conversion.dart';
import 'voice_service.dart';

/// The playback surface TTS-consuming controllers depend on.
abstract interface class AudioSink {
  /// Fires when playback finishes on its own — the hands-free loop uses this
  /// to return to listening after speaking.
  Stream<void> get onComplete;

  /// Play [audio] (stops anything already playing first).
  Future<void> play(SynthesizedAudio audio);

  /// Barge-in: cut playback immediately.
  Future<void> stop();

  Future<void> dispose();
}

final class VoicePlayer implements AudioSink {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> play(SynthesizedAudio audio) async {
    await _player.stop();
    final wav = floatSamplesToWav(audio.samples, audio.sampleRate);
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
