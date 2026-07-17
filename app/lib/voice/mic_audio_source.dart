/// Thin `record` adapter: the device mic as a `Stream<Float32List>` of 16 kHz
/// mono samples, ready to feed [VoiceService.segment]/[transcribeStream].
///
/// Platform glue only — it holds no logic worth unit-testing and can't run under
/// `flutter test` (needs a real mic + platform channels), so it's excluded from
/// the coverage floor (like `llama_engine_service.dart`). The conversion it
/// relies on (`pcm16ToFloat32`) is pure and IS tested.
///
/// [MicSource] is the seam Loop 6 T2's voice UI controllers depend on instead
/// of this concrete class — same discipline as [VoiceService]/
/// `FakeVoiceService`: `features/voice` never imports `record` directly, and
/// widget tests override `micSourceProvider` with `FakeMicSource`
/// (`fake_mic_source.dart`, lib-resident) to drive hold-to-talk/hands-free
/// without a real mic.
library;

import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_conversion.dart';
import 'voice_service.dart';

/// The one sample rate the whole voice pipeline runs at (whisper + Silero VAD
/// both expect 16 kHz mono).
const voiceSampleRate = 16000;

/// The mic-capture surface [VoiceInputController]/hands-free mode depend on.
abstract interface class MicSource {
  /// Whether the mic permission is granted (requests it if not yet decided).
  Future<bool> hasPermission();

  /// Start capturing and return the normalized float32 sample stream. Throws a
  /// [VoiceValidationFailure] if permission is denied — the caller shows the
  /// mic-permission affordance rather than opening a dead stream.
  Future<Stream<Float32List>> start();

  /// Stop capturing (ends the stream).
  Future<void> stop();

  Future<void> dispose();
}

final class MicAudioSource implements MicSource {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Float32List>> start() async {
    if (!await _recorder.hasPermission()) {
      throw const VoiceValidationFailure('microphone permission denied');
    }
    final bytes = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: voiceSampleRate,
        numChannels: 1,
      ),
    );
    return bytes.map(pcm16ToFloat32);
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
