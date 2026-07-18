/// [VoiceService] backed by `sherpa_onnx` 1.13.4 (STT + TTS + Silero VAD in one
/// Apache-2.0 package), running on a dedicated worker isolate we own.
///
/// ## Why an owned isolate
///
/// Whisper decode is heavy and must not touch the root isolate (ADR-002). All
/// sherpa objects hold native `Pointer`s that cannot cross an isolate boundary,
/// so — exactly like `LlamaEngineService` — one long-lived worker owns the
/// native handles (recognizer / tts / vad) and the main isolate only posts
/// commands and awaits results over `SendPort`s. VAD stepping is light but runs
/// on the worker too, for one place that owns `initBindings` and the handles.
///
/// ## Native library resolution
///
/// On device (Android/iOS/macOS release) sherpa's platform packages put the
/// dylib where the loader finds it by default → [libraryDirectory] is null. For
/// `flutter test` on this dev machine the dylib isn't on the default search
/// path, so tests pass the pub-cache `sherpa_onnx_macos/macos` directory (and
/// that copy must be ad-hoc re-signed once — the shipped arm64 signature is
/// invalid and macOS SIGKILLs it otherwise; see the integration test's setup).
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice_service.dart';

final class SherpaVoiceService implements VoiceService {
  /// Directory holding the sherpa native library, or null to use the platform
  /// default search path (production). See the class doc.
  final String? libraryDirectory;

  SherpaVoiceService({this.libraryDirectory});

  Isolate? _isolate;
  SendPort? _commands;
  final _responses = ReceivePort();
  final _pending = <int, Completer<Object?>>{};
  int _nextId = 0;
  Future<void>? _starting;
  bool _disposed = false;

  bool _asrReady = false;
  bool _ttsReady = false;
  bool _vadReady = false;

  @override
  bool get isAsrReady => _asrReady && !_disposed;
  @override
  bool get isTtsReady => _ttsReady && !_disposed;
  @override
  bool get isVadReady => _vadReady && !_disposed;

  // --- isolate lifecycle ---------------------------------------------------

  Future<void> _ensureStarted() {
    if (_disposed) {
      throw const VoiceDisposedFailure('voice service has been disposed');
    }
    return _starting ??= _start();
  }

  Future<void> _start() async {
    _responses.listen(_onResponse);
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(
      _voiceWorkerMain,
      _Boot(ready.sendPort, _responses.sendPort, libraryDirectory),
      debugName: 'dhruva-voice',
    );
    _commands = await ready.first as SendPort;
    ready.close();
  }

  void _onResponse(Object? message) {
    if (message is! _Response) return;
    final completer = _pending.remove(message.id);
    if (completer == null) return;
    if (message.error != null) {
      completer.completeError(_failureFrom(message.error!));
    } else {
      completer.complete(message.payload);
    }
  }

  Future<T> _request<T>(_Command command) async {
    await _ensureStarted();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    // ponytail: one shared response port + id/completer correlation (not a port
    // per request) — keeps VAD's chunk-rate traffic cheap.
    _commands!.send(_Request(id, command));
    return await completer.future as T;
  }

  // --- model loading -------------------------------------------------------

  @override
  Future<void> loadAsr(AsrModelConfig config) async {
    await _request<void>(_LoadAsr(config));
    _asrReady = true;
  }

  @override
  Future<void> loadTts(TtsModelConfig config) async {
    await _request<void>(_LoadTts(config));
    _ttsReady = true;
  }

  @override
  Future<void> loadVad(VadConfig config) async {
    await _request<void>(_LoadVad(config));
    _vadReady = true;
  }

  // --- transcribe ----------------------------------------------------------

  @override
  Future<Transcript> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    if (!isAsrReady) {
      throw const VoiceDisposedFailure('no ASR model loaded; call loadAsr()');
    }
    final r = await _request<_TranscribeResult>(
      _Transcribe(samples, sampleRate),
    );
    return Transcript(
      r.text,
      isFinal: true,
      language: r.language.isEmpty ? null : r.language,
    );
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

  // --- synthesize ----------------------------------------------------------

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
    final r = await _request<_SynthResult>(_Synthesize(text, voiceId, speed));
    return SynthesizedAudio(r.samples, r.sampleRate);
  }

  // --- VAD / turn-taking ---------------------------------------------------

  @override
  Stream<VadEvent> segment(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
  }) async* {
    if (!isVadReady) {
      throw const VoiceDisposedFailure('no VAD model loaded; call loadVad()');
    }
    await _request<void>(const _VadReset());
    var speaking = false;
    var pos = 0;
    try {
      await for (final chunk in audio) {
        final reply = await _request<_VadReply>(_VadAccept(chunk));
        pos += chunk.length;
        if (reply.isSpeaking && !speaking) {
          speaking = true;
          yield SpeechStarted(pos * 1000 ~/ sampleRate);
        } else if (!reply.isSpeaking && speaking) {
          speaking = false;
        }
        for (final seg in reply.segments) {
          yield _segmentEvent(seg, sampleRate);
        }
      }
      final flushed = await _request<_VadReply>(const _VadFlush());
      for (final seg in flushed.segments) {
        yield _segmentEvent(seg, sampleRate);
      }
    } finally {
      // Reset so the next stream starts clean, even on early cancel.
      if (!_disposed) {
        await _request<void>(const _VadReset()).catchError((_) {});
      }
    }
  }

  SpeechEnded _segmentEvent(_SegData seg, int sampleRate) => SpeechEnded(
    seg.samples,
    seg.startSample * 1000 ~/ sampleRate,
    seg.samples.length * 1000 ~/ sampleRate,
  );

  // --- cancel / dispose ----------------------------------------------------

  @override
  Future<void> cancel() async {
    if (_disposed || _commands == null) return;
    // Native transcribe/synth calls are synchronous on the worker and can't be
    // interrupted mid-call (whisper-tiny on a short utterance is ~1s); barge-in
    // is realized by the caller stopping TTS *playback* + this resetting the
    // VAD so the next turn starts clean.
    await _request<void>(const _VadReset()).catchError((_) {});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (_commands != null) {
        await _request<void>(
          const _Dispose(),
        ).timeout(const Duration(seconds: 2), onTimeout: () {});
      }
    } catch (_) {
      // Worker already gone / never started — killing the isolate is enough.
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _responses.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(const VoiceDisposedFailure('service disposed'));
      }
    }
    _pending.clear();
  }

  VoiceFailure _failureFrom(_ErrPayload e) {
    return switch (e.type) {
      'load' => VoiceModelLoadFailure(e.message),
      'transcribe' => VoiceTranscribeFailure(e.message),
      'synthesize' => VoiceSynthesizeFailure(e.message),
      'validation' => VoiceValidationFailure(e.message),
      'disposed' => VoiceDisposedFailure(e.message),
      _ => VoiceUnknownFailure(e.message),
    };
  }
}

// ===========================================================================
// Isolate message protocol
// ===========================================================================

final class _Boot {
  final SendPort ready;
  final SendPort responses;
  final String? libraryDirectory;
  const _Boot(this.ready, this.responses, this.libraryDirectory);
}

final class _Request {
  final int id;
  final _Command command;
  const _Request(this.id, this.command);
}

final class _Response {
  final int id;
  final Object? payload;
  final _ErrPayload? error;
  const _Response(this.id, {this.payload, this.error});
}

final class _ErrPayload {
  final String type;
  final String message;
  const _ErrPayload(this.type, this.message);
}

sealed class _Command {
  const _Command();
}

final class _LoadAsr extends _Command {
  final AsrModelConfig config;
  const _LoadAsr(this.config);
}

final class _LoadTts extends _Command {
  final TtsModelConfig config;
  const _LoadTts(this.config);
}

final class _LoadVad extends _Command {
  final VadConfig config;
  const _LoadVad(this.config);
}

final class _Transcribe extends _Command {
  final Float32List samples;
  final int sampleRate;
  const _Transcribe(this.samples, this.sampleRate);
}

final class _Synthesize extends _Command {
  final String text;
  final int voiceId;
  final double speed;
  const _Synthesize(this.text, this.voiceId, this.speed);
}

final class _VadAccept extends _Command {
  final Float32List samples;
  const _VadAccept(this.samples);
}

final class _VadFlush extends _Command {
  const _VadFlush();
}

final class _VadReset extends _Command {
  const _VadReset();
}

final class _Dispose extends _Command {
  const _Dispose();
}

final class _TranscribeResult {
  final String text;
  final String language;
  const _TranscribeResult(this.text, this.language);
}

final class _SynthResult {
  final Float32List samples;
  final int sampleRate;
  const _SynthResult(this.samples, this.sampleRate);
}

final class _SegData {
  final Float32List samples;
  final int startSample;
  const _SegData(this.samples, this.startSample);
}

final class _VadReply {
  final List<_SegData> segments;
  final bool isSpeaking;
  const _VadReply(this.segments, this.isSpeaking);
}

// ===========================================================================
// Worker isolate
// ===========================================================================

void _voiceWorkerMain(_Boot boot) {
  sherpa.initBindings(boot.libraryDirectory);
  final worker = _VoiceWorker(boot.responses);
  final commands = ReceivePort();
  boot.ready.send(commands.sendPort);
  commands.listen((message) {
    if (message is _Request) worker.handle(message);
  });
}

final class _VoiceWorker {
  final SendPort _responses;
  _VoiceWorker(this._responses);

  sherpa.OfflineRecognizer? _asr;
  sherpa.OfflineTts? _tts;
  sherpa.VoiceActivityDetector? _vad;

  void handle(_Request request) {
    try {
      final payload = _dispatch(request.command);
      _responses.send(_Response(request.id, payload: payload));
    } on VoiceFailure catch (e) {
      _responses.send(
        _Response(request.id, error: _ErrPayload(_typeOf(e), e.message)),
      );
    } catch (e) {
      _responses.send(
        _Response(request.id, error: _ErrPayload('unknown', e.toString())),
      );
    }
  }

  Object? _dispatch(_Command command) {
    switch (command) {
      case _LoadAsr(:final config):
        _loadAsr(config);
        return null;
      case _LoadTts(:final config):
        _loadTts(config);
        return null;
      case _LoadVad(:final config):
        _loadVad(config);
        return null;
      case _Transcribe(:final samples, :final sampleRate):
        return _transcribe(samples, sampleRate);
      case _Synthesize(:final text, :final voiceId, :final speed):
        return _synthesize(text, voiceId, speed);
      case _VadAccept(:final samples):
        return _vadAccept(samples);
      case _VadFlush():
        return _vadFlush();
      case _VadReset():
        _vad?.reset();
        return null;
      case _Dispose():
        _freeAll();
        return null;
    }
  }

  void _loadAsr(AsrModelConfig config) {
    _asr?.free();
    _asr = null;
    try {
      final model = sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: config.encoder,
          decoder: config.decoder,
          language: config.language,
        ),
        tokens: config.tokens,
        modelType: 'whisper',
        numThreads: 2,
        debug: false,
      );
      _asr = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(model: model),
      );
    } catch (e) {
      throw VoiceModelLoadFailure('failed to load ASR model', cause: e);
    }
  }

  void _loadTts(TtsModelConfig config) {
    _tts?.free();
    _tts = null;
    try {
      final model = sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: config.model,
          tokens: config.tokens,
          dataDir: config.dataDir,
        ),
        numThreads: 2,
        debug: false,
      );
      _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: model));
    } catch (e) {
      throw VoiceModelLoadFailure('failed to load TTS voice', cause: e);
    }
  }

  void _loadVad(VadConfig config) {
    _vad?.free();
    _vad = null;
    try {
      final vadConfig = sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: config.model,
          threshold: config.threshold,
          minSilenceDuration: config.minSilenceDuration,
          minSpeechDuration: config.minSpeechDuration,
          // Without this sherpa defaults to 5.0s and chops any longer
          // utterance mid-word (see VadConfig.maxSpeechDuration).
          maxSpeechDuration: config.maxSpeechDuration,
        ),
        numThreads: 1,
        debug: false,
      );
      _vad = sherpa.VoiceActivityDetector(
        config: vadConfig,
        bufferSizeInSeconds: 30,
      );
    } catch (e) {
      throw VoiceModelLoadFailure('failed to load VAD model', cause: e);
    }
  }

  _TranscribeResult _transcribe(Float32List samples, int sampleRate) {
    final asr = _asr;
    if (asr == null) {
      throw const VoiceDisposedFailure('no ASR model loaded');
    }
    final stream = asr.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      asr.decode(stream);
      final result = asr.getResult(stream);
      return _TranscribeResult(result.text.trim(), result.lang);
    } catch (e) {
      throw VoiceTranscribeFailure('ASR decode failed', cause: e);
    } finally {
      stream.free();
    }
  }

  _SynthResult _synthesize(String text, int voiceId, double speed) {
    final tts = _tts;
    if (tts == null) {
      throw const VoiceDisposedFailure('no TTS voice loaded');
    }
    final sherpa.GeneratedAudio audio;
    try {
      audio = tts.generate(text: text, sid: voiceId, speed: speed);
    } catch (e) {
      throw VoiceSynthesizeFailure('TTS synthesis failed', cause: e);
    }
    if (audio.samples.isEmpty) {
      throw const VoiceSynthesizeFailure('TTS produced no audio');
    }
    return _SynthResult(audio.samples, audio.sampleRate);
  }

  _VadReply _vadAccept(Float32List samples) {
    final vad = _vad;
    if (vad == null) throw const VoiceDisposedFailure('no VAD model loaded');
    vad.acceptWaveform(samples);
    return _drain(vad);
  }

  _VadReply _vadFlush() {
    final vad = _vad;
    if (vad == null) throw const VoiceDisposedFailure('no VAD model loaded');
    vad.flush();
    return _drain(vad, speakingAfter: false);
  }

  _VadReply _drain(sherpa.VoiceActivityDetector vad, {bool? speakingAfter}) {
    final segments = <_SegData>[];
    while (!vad.isEmpty()) {
      final seg = vad.front();
      segments.add(_SegData(seg.samples, seg.start));
      vad.pop();
    }
    return _VadReply(segments, speakingAfter ?? vad.isDetected());
  }

  void _freeAll() {
    _asr?.free();
    _tts?.free();
    _vad?.free();
    _asr = null;
    _tts = null;
    _vad = null;
  }

  String _typeOf(VoiceFailure e) => switch (e) {
    VoiceModelLoadFailure() => 'load',
    VoiceTranscribeFailure() => 'transcribe',
    VoiceSynthesizeFailure() => 'synthesize',
    VoiceValidationFailure() => 'validation',
    VoiceDisposedFailure() => 'disposed',
    VoiceUnknownFailure() => 'unknown',
  };
}
