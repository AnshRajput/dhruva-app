/// An in-memory [MicSource] for unit/widget tests (mirrors `FakeVoiceService`).
///
/// A test drives it by pushing chunks onto [pushChunk] (or [pushSilence]/
/// [pushSpeech] helpers) after [start] is called — the returned stream only
/// ever emits what the test explicitly feeds it, so hold-to-talk/hands-free
/// controllers can be exercised deterministically without a real mic.
library;

import 'dart:async';
import 'dart:typed_data';

import 'mic_audio_source.dart';
import 'voice_service.dart';

final class FakeMicSource implements MicSource {
  /// Set to false to simulate a denied mic permission.
  bool permissionGranted;

  FakeMicSource({this.permissionGranted = true});

  StreamController<Float32List>? _controller;
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<Stream<Float32List>> start() async {
    if (!permissionGranted) {
      throw const VoiceValidationFailure('microphone permission denied');
    }
    _closeController();
    startCount++;
    // Closed in stop()/dispose(), or above on the next start().
    // ignore: close_sinks
    final controller = StreamController<Float32List>();
    _controller = controller;
    return controller.stream;
  }

  /// Test hook: push one chunk of audio onto the currently-open stream.
  /// No-op if [start] hasn't been called (or the stream was already closed).
  void pushChunk(Float32List chunk) {
    _controller?.add(chunk);
  }

  void pushSilence({int samples = 320}) => pushChunk(Float32List(samples));

  void pushSpeech({int samples = 320, double amplitude = 0.5}) {
    pushChunk(Float32List(samples)..fillRange(0, samples, amplitude));
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _closeController();
  }

  @override
  Future<void> dispose() async {
    _closeController();
  }

  /// `StreamController.close()`'s returned Future only completes once its
  /// `done` event has been delivered to a listener — for a single-
  /// subscription controller that never got one (e.g. a hold torn down
  /// before `transcribeStream(audio).listen(...)` ever ran, the exact race
  /// `voice_input_controller_test.dart`'s "RACE" test drives), that Future
  /// never resolves. Real `MicAudioSource.stop()` has no such quirk (the
  /// `record` package's stop doesn't wait on Dart-stream listener
  /// bookkeeping), so this fake shouldn't either — fire the close, don't
  /// await it.
  void _closeController() {
    unawaited(_controller?.close());
    _controller = null;
  }
}
