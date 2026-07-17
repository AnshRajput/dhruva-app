/// An in-memory [AudioSink] for unit/widget tests (mirrors `FakeVoiceService`
/// / `FakeMicSource`). Records what it was asked to play; [onComplete] fires
/// only when the test calls [completeNow], so a test controls exactly when
/// "TTS finished speaking" happens (hands-free's Speaking -> Listening
/// transition depends on this timing).
library;

import 'dart:async';

import 'voice_player.dart';
import 'voice_service.dart';

final class FakeAudioSink implements AudioSink {
  final _completeController = StreamController<void>.broadcast();

  int playCount = 0;
  int stopCount = 0;
  SynthesizedAudio? lastPlayed;
  bool disposed = false;

  @override
  Stream<void> get onComplete => _completeController.stream;

  @override
  Future<void> play(SynthesizedAudio audio) async {
    playCount++;
    lastPlayed = audio;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  /// Test hook: simulate playback finishing on its own.
  void completeNow() => _completeController.add(null);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _completeController.close();
  }
}
