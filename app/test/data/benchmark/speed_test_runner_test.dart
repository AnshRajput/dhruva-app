import 'dart:async';

import 'package:dhruva/data/benchmark/speed_test_runner.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Engine whose "time" is a shared fake clock it advances itself, so the
/// runner's math is exact and the test needs no real waiting.
class _TimedEngine implements EngineService {
  _TimedEngine(this.clock, {this.tokens = 64, this.promptTokens = 0});

  final _Clock clock;
  final int tokens;
  final int promptTokens;
  String? loadedPath;
  String? lastPrompt;
  EngineGenerateParams? lastParams;
  bool throwOnLoad = false;

  static const loadTime = Duration(milliseconds: 2000);
  static const prefillTime = Duration(milliseconds: 500);
  static const perToken = Duration(milliseconds: 50);

  @override
  bool get isLoaded => loadedPath != null;
  @override
  bool get isMultimodal => false;

  @override
  Future<void> load(
    String modelPath, {
    EngineLoadParams params = const EngineLoadParams(),
  }) async {
    if (throwOnLoad) throw const EngineLoadFailure('bad file');
    clock.now += loadTime;
    loadedPath = modelPath;
  }

  @override
  Stream<EngineEvent> generate({
    String? prompt,
    List<ChatTurn>? messages,
    EngineGenerateParams params = const EngineGenerateParams(),
  }) async* {
    lastPrompt = prompt;
    lastParams = params;
    for (var i = 0; i < tokens; i++) {
      clock.now += i == 0 ? prefillTime : perToken;
      yield EngineToken(tokenId: i, text: 'x');
    }
    yield EngineCompletion(
      reason: EngineStopReason.maxTokens,
      tokenCount: tokens,
      promptTokensDecoded: promptTokens,
    );
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> unload() async => loadedPath = null;
  @override
  Future<void> dispose() async {}
}

class _Clock {
  Duration now = Duration.zero;
}

/// Streams tokens until [cancel], to exercise cancellation.
class _HangingEngine extends _TimedEngine {
  _HangingEngine(super.clock);
  final _ctl = StreamController<EngineEvent>();
  final started = Completer<void>();

  @override
  Stream<EngineEvent> generate({
    String? prompt,
    List<ChatTurn>? messages,
    EngineGenerateParams params = const EngineGenerateParams(),
  }) {
    started.complete();
    return _ctl.stream;
  }

  @override
  Future<void> cancel() async {
    _ctl.add(
      const EngineCompletion(reason: EngineStopReason.cancelled, tokenCount: 0),
    );
    await _ctl.close();
  }
}

SpeedTestRunner _runner(_TimedEngine e, _Clock c) => SpeedTestRunner(
  e,
  appVersion: '1.2.3',
  now: () => DateTime.utc(2026, 11, 1, 12),
  clock: () => c.now,
);

void main() {
  test('computes load ms, prefill tok/s and decode tok/s', () async {
    final clock = _Clock();
    final engine = _TimedEngine(clock);
    final phases = <SpeedTestPhase>[];

    final r = await _runner(
      engine,
      clock,
    ).run('/m/model.gguf', onPhase: phases.add);

    expect(engine.loadedPath, '/m/model.gguf');
    expect(engine.lastPrompt, kSpeedTestPrompt);
    expect(engine.lastParams!.greedy, isTrue);
    expect(engine.lastParams!.maxTokens, 64);
    expect(r.loadMs, 2000);
    // No engine prompt count -> nominal 128 tokens over 0.5s to first token.
    expect(r.prefillTps, closeTo(128 / 0.5, 1e-9));
    // 63 inter-token gaps of 50ms after the first token: 63 / 3.15s = 20.
    expect(r.decodeTps, closeTo(20, 1e-9));
    expect(r.measuredAt, DateTime.utc(2026, 11, 1, 12));
    expect(r.appVersion, '1.2.3');
    expect(phases, [
      SpeedTestPhase.loading,
      SpeedTestPhase.prefilling,
      SpeedTestPhase.decoding,
    ]);
  });

  test('prefers the engine-reported prompt token count', () async {
    final clock = _Clock();
    final r = await _runner(
      _TimedEngine(clock, promptTokens: 100),
      clock,
    ).run('/m.gguf');
    expect(r.prefillTps, closeTo(100 / 0.5, 1e-9));
  });

  test('too few tokens is reported, not a bogus rate', () async {
    final clock = _Clock();
    await expectLater(
      _runner(_TimedEngine(clock, tokens: 3), clock).run('/m.gguf'),
      throwsA(isA<SpeedTestTooShort>()),
    );
  });

  test('engine load failure propagates', () async {
    final clock = _Clock();
    final engine = _TimedEngine(clock)..throwOnLoad = true;
    await expectLater(
      _runner(engine, clock).run('/m.gguf'),
      throwsA(isA<EngineLoadFailure>()),
    );
  });

  test('cancel mid-generation throws SpeedTestCancelled', () async {
    final clock = _Clock();
    final engine = _HangingEngine(clock);
    final runner = _runner(engine, clock);
    final run = runner.run('/m.gguf');
    final expectation = expectLater(run, throwsA(isA<SpeedTestCancelled>()));
    await engine.started.future;
    await runner.cancel();
    await expectation;
  });

  test('cancel during load aborts before generating', () async {
    final clock = _Clock();
    final engine = _TimedEngine(clock);
    final runner = _runner(engine, clock);
    final run = runner.run('/m.gguf');
    final expectation = expectLater(run, throwsA(isA<SpeedTestCancelled>()));
    await runner.cancel();
    await expectation;
    expect(engine.lastPrompt, isNull);
  });
}
