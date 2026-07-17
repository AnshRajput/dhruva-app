/// Thin `audioplayers` adapter: play synthesized speech, and — the part that
/// matters for barge-in — [stop] it instantly when the user starts talking.
///
/// Platform glue only (no testable logic, needs a real audio device), so it's
/// excluded from the coverage floor. [SynthesizedAudio] → WAV bytes conversion
/// lives in the pure, tested `floatSamplesToWav`.
library;

import 'package:audioplayers/audioplayers.dart';

import 'audio_conversion.dart';
import 'voice_service.dart';

final class VoicePlayer {
  final AudioPlayer _player = AudioPlayer();

  /// Fires when playback finishes on its own — the hands-free loop uses this to
  /// return to listening after speaking.
  Stream<void> get onComplete => _player.onPlayerComplete;

  /// Play [audio] (stops anything already playing first).
  Future<void> play(SynthesizedAudio audio) async {
    await _player.stop();
    final wav = floatSamplesToWav(audio.samples, audio.sampleRate);
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  /// Barge-in: cut playback immediately.
  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}
