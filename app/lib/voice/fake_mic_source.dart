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
    await _controller?.close();
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
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await _controller?.close();
    _controller = null;
  }
}
