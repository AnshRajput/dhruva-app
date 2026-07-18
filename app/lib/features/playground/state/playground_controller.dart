/// Playground: run ONE prompt through TWO installed models and compare their
/// streaming replies + live tok/s side by side, with live sampling controls
/// (VIDEO_FIXES.md P2 #7; PlaygroundMock.astro).
///
/// ADR-001 is single-session — the app owns one native context, one model
/// loaded at a time, on `llama_cpp_dart`'s own worker isolate. So "side by
/// side" is COMPUTED SEQUENTIALLY: load + stream model A through the shared
/// [engineServiceProvider], then load + stream model B through the same engine.
/// Both replies stay on screen together; only their generation is serialized.
/// No second engine, no root-isolate inference, no new native surface.
///
/// Engine hand-back: a run ends by [EngineService.unload]-ing. That's what lets
/// `features/chat` stay untouched — its `ensureModelLoaded` guard is
/// `loadedModelId == modelId && engine.isLoaded`, so an unloaded engine makes it
/// reload its own model on the next send regardless of the (now-stale) tracker
/// it keeps. Nothing here imports or writes that tracker (ADR-002).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../engine_bindings/engine_service.dart';

/// Lifecycle of one model's column in the compare. [queued] is the
/// not-yet-started column while the other model runs — the phone runs one
/// model at a time (ADR-001), so the two runs are serialized, not simultaneous.
enum RunStatus { idle, queued, loading, streaming, done, error, cancelled }

/// One model's output column.
final class RunSlot {
  final String text;

  /// Trailing-1s tokens/sec while [RunStatus.streaming]; 0 otherwise.
  final double liveTokPerSec;

  /// Authoritative rate once the run finishes (tokenCount / elapsed).
  final double finalTokPerSec;
  final RunStatus status;
  final String? error;

  const RunSlot({
    this.text = '',
    this.liveTokPerSec = 0,
    this.finalTokPerSec = 0,
    this.status = RunStatus.idle,
    this.error,
  });

  RunSlot copyWith({
    String? text,
    double? liveTokPerSec,
    double? finalTokPerSec,
    RunStatus? status,
  }) => RunSlot(
    text: text ?? this.text,
    liveTokPerSec: liveTokPerSec ?? this.liveTokPerSec,
    finalTokPerSec: finalTokPerSec ?? this.finalTokPerSec,
    status: status ?? this.status,
    error: error,
  );
}

final class PlaygroundState {
  /// Selected installed-model row ids, or null until the user (or the UI's
  /// default) picks one. `null` renders as "first installed" / "second
  /// installed" in the UI, so no mid-build seeding is needed here.
  final int? modelAId;
  final int? modelBId;
  final double temperature;
  final double topP;
  final int maxTokens;
  final RunSlot runA;
  final RunSlot runB;
  final bool isRunning;

  const PlaygroundState({
    this.modelAId,
    this.modelBId,
    this.temperature = 0.8,
    this.topP = 0.95,
    this.maxTokens = 256,
    this.runA = const RunSlot(),
    this.runB = const RunSlot(),
    this.isRunning = false,
  });

  PlaygroundState copyWith({
    int? modelAId,
    int? modelBId,
    double? temperature,
    double? topP,
    int? maxTokens,
    RunSlot? runA,
    RunSlot? runB,
    bool? isRunning,
  }) => PlaygroundState(
    modelAId: modelAId ?? this.modelAId,
    modelBId: modelBId ?? this.modelBId,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    maxTokens: maxTokens ?? this.maxTokens,
    runA: runA ?? this.runA,
    runB: runB ?? this.runB,
    isRunning: isRunning ?? this.isRunning,
  );
}

/// App-scoped (not autoDispose): one Playground, one controller for the
/// session. Nothing family-keyed, and keeping it alive across bottom-nav
/// switches avoids losing an in-flight run when the user peeks at another tab.
final playgroundControllerProvider =
    NotifierProvider<PlaygroundController, PlaygroundState>(
      PlaygroundController.new,
    );

/// Same 100ms batching budget chat uses (`DhruvaTokens.motion.instant`) — never
/// a state rebuild per token.
const _flushInterval = Duration(milliseconds: 100);

class PlaygroundController extends Notifier<PlaygroundState> {
  StreamSubscription<EngineEvent>? _sub;
  Timer? _flushTimer;
  final List<DateTime> _arrivals = [];
  String _buffer = '';
  bool _aborted = false;

  @override
  PlaygroundState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _flushTimer?.cancel();
    });
    return const PlaygroundState();
  }

  // Swapping a model invalidates that column's stale result (text/tok-s and
  // any "Fastest" badge), so reset its slot to idle when the selection changes.
  void setModelA(int id) =>
      state = state.copyWith(modelAId: id, runA: const RunSlot());
  void setModelB(int id) =>
      state = state.copyWith(modelBId: id, runB: const RunSlot());
  void setTemperature(double v) => state = state.copyWith(temperature: v);
  void setTopP(double v) => state = state.copyWith(topP: v);
  void setMaxTokens(int v) => state = state.copyWith(maxTokens: v);

  /// Runs [prompt] through [modelA] then [modelB]. No-op on an empty prompt or
  /// while a run is already in flight. Always releases the engine at the end.
  Future<void> run({
    required String prompt,
    required InstalledModelInfo modelA,
    required InstalledModelInfo modelB,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || state.isRunning) return;
    _aborted = false;
    // Model B waits its turn while A loads + streams (single-session, ADR-001),
    // so mark it queued rather than idle/"Ready" — it never reads as inert.
    state = state.copyWith(
      isRunning: true,
      runA: const RunSlot(status: RunStatus.idle),
      runB: const RunSlot(status: RunStatus.queued),
    );
    final engine = ref.read(engineServiceProvider);
    try {
      await _runSlot(engine, modelA, isA: true, prompt: trimmed);
      if (!_aborted) {
        await _runSlot(engine, modelB, isA: false, prompt: trimmed);
      }
    } finally {
      _flushTimer?.cancel();
      // Hand the shared single-session engine back (see header) so chat
      // reloads its own model on the next send.
      await engine.unload();
      state = state.copyWith(isRunning: false);
    }
  }

  /// Stops the in-flight run cooperatively and skips the not-yet-started model.
  Future<void> cancel() async {
    if (!state.isRunning) return;
    _aborted = true;
    await ref.read(engineServiceProvider).cancel();
  }

  Future<void> _runSlot(
    EngineService engine,
    InstalledModelInfo model, {
    required bool isA,
    required String prompt,
  }) async {
    _setSlot(isA, const RunSlot(status: RunStatus.loading));
    try {
      await engine.load(model.localPath);
    } on EngineFailure catch (e) {
      _setSlot(isA, RunSlot(status: RunStatus.error, error: e.message));
      return;
    }
    if (_aborted) return;

    _buffer = '';
    _arrivals.clear();
    _setSlot(isA, const RunSlot(status: RunStatus.streaming));

    final params = EngineGenerateParams(
      maxTokens: state.maxTokens,
      temperature: state.temperature,
      topP: state.topP,
    );
    final completer = Completer<void>();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush(isA));
    _sub = engine
        .generate(prompt: prompt, params: params)
        .listen(
          (event) {
            switch (event) {
              case EngineToken():
                _buffer += event.text;
                _arrivals.add(DateTime.now());
              case EngineCompletion():
                _flushTimer?.cancel();
                _flush(isA);
                final tps = event.elapsedMs > 0
                    ? event.tokenCount * 1000 / event.elapsedMs
                    : 0.0;
                final status = event.reason == EngineStopReason.cancelled
                    ? RunStatus.cancelled
                    : RunStatus.done;
                _setSlot(
                  isA,
                  _slot(isA).copyWith(
                    status: status,
                    finalTokPerSec: tps,
                    liveTokPerSec: 0,
                  ),
                );
            }
          },
          onError: (Object e) {
            _flushTimer?.cancel();
            final msg = e is EngineFailure ? e.message : e.toString();
            _setSlot(
              isA,
              RunSlot(text: _buffer, status: RunStatus.error, error: msg),
            );
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );
    await completer.future;
    // The stream has already terminated (onDone/onError above) — the
    // subscription auto-cancels. Do NOT `await _sub.cancel()` here: the shared
    // single-session engine serializes runs by unloading between them, and
    // cancelling an already-done subscription strands that unload's pending
    // stream close (no listener left to deliver `done` to), deadlocking the
    // next model's load. `onDispose` (build) still cancels a live sub if the
    // controller is torn down mid-run. Mirrors `chat_controller`'s
    // `_resetStreamState`, which nulls the ref without cancelling.
    _sub = null;
  }

  void _flush(bool isA) {
    final now = DateTime.now();
    _arrivals.removeWhere(
      (t) => now.difference(t) > const Duration(seconds: 1),
    );
    _setSlot(
      isA,
      _slot(isA).copyWith(
        text: _buffer,
        liveTokPerSec: _arrivals.length.toDouble(),
        status: RunStatus.streaming,
      ),
    );
  }

  RunSlot _slot(bool isA) => isA ? state.runA : state.runB;

  void _setSlot(bool isA, RunSlot slot) =>
      state = isA ? state.copyWith(runA: slot) : state.copyWith(runB: slot);
}
