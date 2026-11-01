/// Drives speed tests from the Installed tab: one model or the whole list,
/// one at a time on the single engine, cancellable. Results are persisted by
/// `speedResultsProvider` (JSON file, no Drift). Never runs while chat is
/// using the engine (`EngineLease`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/engine_session.dart';
import '../../../core/di/providers.dart';
import '../../../core/di/speed_providers.dart';
import '../../../data/benchmark/speed_result.dart';
import '../../../data/benchmark/speed_test_runner.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../engine_bindings/engine_service.dart';

final class SpeedTestState {
  /// True from the first model's load until the whole run ends.
  final bool active;

  /// [speedKey] of the model being measured, if any.
  final String? runningKey;
  final SpeedTestPhase? phase;

  /// Keys still waiting their turn (excludes [runningKey]).
  final List<String> queued;
  final int completed;
  final int total;

  /// Plain-language failure per model key, from the most recent attempt.
  final Map<String, String> failures;

  /// Shown when a run could not start (e.g. chat is replying).
  final String? notice;

  const SpeedTestState({
    this.active = false,
    this.runningKey,
    this.phase,
    this.queued = const [],
    this.completed = 0,
    this.total = 0,
    this.failures = const {},
    this.notice,
  });

  SpeedTestState copyWith({
    bool? active,
    String? runningKey,
    SpeedTestPhase? phase,
    List<String>? queued,
    int? completed,
    int? total,
    Map<String, String>? failures,
    String? notice,
    bool clearRunning = false,
    bool clearNotice = false,
  }) => SpeedTestState(
    active: active ?? this.active,
    runningKey: clearRunning ? null : (runningKey ?? this.runningKey),
    phase: clearRunning ? null : (phase ?? this.phase),
    queued: queued ?? this.queued,
    completed: completed ?? this.completed,
    total: total ?? this.total,
    failures: failures ?? this.failures,
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}

final speedTestControllerProvider =
    NotifierProvider<SpeedTestController, SpeedTestState>(
      SpeedTestController.new,
    );

class SpeedTestController extends Notifier<SpeedTestState> {
  SpeedTestRunner? _runner;
  bool _stop = false;

  @override
  SpeedTestState build() => const SpeedTestState();

  /// Tests [models] one after another. No-op if a run is already active.
  Future<void> run(List<InstalledModelInfo> models) async {
    if (models.isEmpty || state.active) return;
    final lease = ref.read(engineLeaseProvider);
    if (!lease.tryStartSpeedTest()) {
      state = state.copyWith(
        notice: 'Your chat is still busy. Try again when it finishes replying.',
      );
      return;
    }
    final engine = ref.read(engineServiceProvider);
    // The speed test swaps whatever model chat had loaded; make chat reload.
    ref.read(loadedModelIdProvider.notifier).set(null);
    _stop = false;
    final keys = [for (final m in models) speedKey(m.repoId, m.fileName)];
    state = SpeedTestState(
      active: true,
      queued: keys,
      total: models.length,
      failures: {
        for (final e in state.failures.entries)
          if (!keys.contains(e.key)) e.key: e.value,
      },
    );
    try {
      for (var i = 0; i < models.length && !_stop; i++) {
        final m = models[i];
        final key = keys[i];
        state = state.copyWith(
          runningKey: key,
          phase: SpeedTestPhase.loading,
          queued: keys.sublist(i + 1),
          completed: i,
        );
        final runner = _runner = SpeedTestRunner(
          engine,
          appVersion: ref.read(appVersionProvider),
        );
        try {
          final result = await runner.run(
            m.localPath,
            onPhase: (phase) => state = state.copyWith(phase: phase),
          );
          await ref.read(speedResultsProvider.notifier).save(key, result);
        } on SpeedTestCancelled {
          break;
        } on SpeedTestTooShort {
          _fail(key, 'This model stopped answering too soon to be measured.');
        } on EngineOutOfMemoryFailure {
          _fail(key, 'Not enough free memory to test this model right now.');
        } on EngineFailure {
          _fail(key, "Couldn't load this model to test it.");
        }
      }
    } finally {
      _runner = null;
      try {
        await engine.unload();
      } catch (_) {
        // Best effort: chat reloads its own model on demand anyway.
      }
      lease.endSpeedTest();
      state = SpeedTestState(failures: state.failures);
    }
  }

  Future<void> cancel() async {
    if (!state.active) return;
    _stop = true;
    await _runner?.cancel();
  }

  void _fail(String key, String message) {
    state = state.copyWith(failures: {...state.failures, key: message});
  }
}

/// "Run a 20-second speed test?" offers, raised once per model right after it
/// finishes downloading or importing. Dismissible; never re-raised.
final speedTestOfferProvider =
    NotifierProvider<SpeedTestOfferNotifier, List<String>>(
      SpeedTestOfferNotifier.new,
    );

class SpeedTestOfferNotifier extends Notifier<List<String>> {
  final Set<String> _everOffered = {};

  @override
  List<String> build() => const [];

  void offer(String key) {
    if (_everOffered.add(key)) state = [...state, key];
  }

  void dismiss(String key) => state = [
    for (final k in state)
      if (k != key) k,
  ];
}
