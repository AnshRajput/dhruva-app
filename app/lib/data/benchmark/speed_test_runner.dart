/// On-device speed test: load -> prefill a fixed ~128-token prompt -> greedily
/// decode 64 tokens. Goes through [EngineService] (its own worker isolate),
/// never the root isolate. Timing is taken on the calling isolate from token
/// arrival, so prefill = time to first token and decode = first -> last token
/// (prefill excluded).
library;

import '../../engine_bindings/engine_service.dart';
import 'speed_result.dart';

const int kSpeedTestDecodeTokens = 64;

/// Nominal prompt length; replaced by the engine's own count when it has one.
const int kSpeedTestPromptTokens = 128;

/// Below this many generated tokens a decode rate is noise.
const int kSpeedTestMinTokens = 8;

// An open-ended passage (~128 tokens of plain English) so even instruct
// models keep writing for the full 64 tokens.
const String kSpeedTestPrompt =
    'The old lighthouse stood at the edge of the cliff, its white paint '
    'peeling after decades of salt and wind. Every evening the keeper climbed '
    'the spiral staircase, lit the great lamp, and watched the ships drift '
    'past on the dark water. He kept a journal of everything he saw: the '
    'storms that rolled in from the north, the fishing boats that returned at '
    'dawn, the gulls that nested on the rocks below, and the strange lights '
    'that sometimes flickered far out at sea. One autumn night, as the fog '
    'thickened and the lamp swept its slow beam across the waves, he noticed '
    'a small wooden boat drifting without a single sail or oar. He put down '
    'his pen, picked up his lantern, and began to write the next page of the '
    'story:';

enum SpeedTestPhase { loading, prefilling, decoding }

class SpeedTestCancelled implements Exception {
  const SpeedTestCancelled();
}

/// The model answered, but too briefly to measure.
class SpeedTestTooShort implements Exception {
  final int tokens;
  const SpeedTestTooShort(this.tokens);
}

class SpeedTestRunner {
  final EngineService _engine;
  final String appVersion;
  final DateTime Function() _now;
  final Duration Function() _clock;

  bool _cancelled = false;
  bool _generating = false;

  SpeedTestRunner(
    this._engine, {
    required this.appVersion,
    DateTime Function()? now,
    Duration Function()? clock,
  }) : _now = now ?? DateTime.now,
       _clock = clock ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  /// Stops the run; [run] then throws [SpeedTestCancelled].
  Future<void> cancel() async {
    _cancelled = true;
    if (_generating) await _engine.cancel();
  }

  /// Runs the full test on [modelPath]. Engine failures propagate as
  /// [EngineFailure]; the caller owns unloading afterwards.
  Future<SpeedResult> run(
    String modelPath, {
    void Function(SpeedTestPhase phase)? onPhase,
  }) async {
    onPhase?.call(SpeedTestPhase.loading);
    final loadStart = _clock();
    await _engine.load(modelPath);
    final loadMs = (_clock() - loadStart).inMilliseconds;
    if (_cancelled) throw const SpeedTestCancelled();

    onPhase?.call(SpeedTestPhase.prefilling);
    final start = _clock();
    Duration? first;
    var last = start;
    var tokens = 0;
    var promptTokens = 0;
    _generating = true;
    try {
      await for (final event in _engine.generate(
        prompt: kSpeedTestPrompt,
        params: const EngineGenerateParams(
          maxTokens: kSpeedTestDecodeTokens,
          greedy: true,
        ),
      )) {
        switch (event) {
          case EngineToken():
            last = _clock();
            if (first == null) {
              first = last;
              onPhase?.call(SpeedTestPhase.decoding);
            }
            tokens++;
          case EngineCompletion():
            promptTokens = event.promptTokensDecoded;
          case EngineHistoryTrimmed():
            break;
        }
      }
    } finally {
      _generating = false;
    }
    if (_cancelled) throw const SpeedTestCancelled();
    if (first == null || tokens < kSpeedTestMinTokens) {
      throw SpeedTestTooShort(tokens);
    }

    final prefillSecs = _secs(first - start);
    final decodeSecs = _secs(last - first);
    return SpeedResult(
      decodeTps: (tokens - 1) / decodeSecs,
      prefillTps:
          (promptTokens > 0 ? promptTokens : kSpeedTestPromptTokens) /
          prefillSecs,
      loadMs: loadMs,
      measuredAt: _now().toUtc(),
      appVersion: appVersion,
    );
  }

  // Floored at 1ms so an instant (fake) clock can't divide by zero.
  static double _secs(Duration d) =>
      (d.inMicroseconds < 1000 ? 1000 : d.inMicroseconds) / 1e6;
}
