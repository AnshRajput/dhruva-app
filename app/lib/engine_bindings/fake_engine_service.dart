/// An in-memory [EngineService] with no native code, for unit/widget tests
/// (ADR-002: one happy path per feature runs over a fake EngineService).
///
/// It faithfully models the contract that matters: streaming token-by-token,
/// cooperative cancellation between tokens, termination on unload, and typed
/// [EngineFailure] surfacing.
library;

import 'dart:async';

import 'engine_service.dart';

final class FakeEngineService implements EngineService {
  /// Tokens emitted per [generate] call (each becomes one [EngineToken]).
  final List<String> scriptedTokens;

  /// Delay between tokens; also the cooperative-cancel checkpoint interval.
  final Duration tokenDelay;

  /// When set, [load] throws this instead of loading.
  final EngineFailure? loadFailure;

  /// When set, [generate]'s stream emits this error instead of tokens.
  final EngineFailure? generateFailure;

  FakeEngineService({
    this.scriptedTokens = const ['Hello', ' ', 'world', '!'],
    this.tokenDelay = const Duration(milliseconds: 10),
    this.loadFailure,
    this.generateFailure,
  });

  bool _loaded = false;
  bool _disposed = false;
  _FakeRun? _run;

  /// Test hook: number of successful [load] calls.
  int loadCount = 0;

  /// Test hook: number of [unload] calls.
  int unloadCount = 0;

  @override
  bool get isLoaded => _loaded && !_disposed;

  @override
  Future<void> load(
    String modelPath, {
    EngineLoadParams params = const EngineLoadParams(),
  }) async {
    if (_disposed) {
      throw const EngineDisposedFailure('engine has been disposed');
    }
    if (loadFailure != null) throw loadFailure!;
    if (_loaded) await unload();
    await Future<void>.delayed(Duration.zero);
    _loaded = true;
    loadCount++;
  }

  @override
  Stream<EngineEvent> generate({
    String? prompt,
    List<ChatTurn>? messages,
    EngineGenerateParams params = const EngineGenerateParams(),
  }) {
    checkGenerateArgs(prompt, messages);
    if (!isLoaded) {
      throw const EngineDisposedFailure('no model loaded; call load() first');
    }
    if (_run != null) {
      throw const EngineDecodeFailure('a generation is already in flight');
    }

    final controller = StreamController<EngineEvent>();
    final run = _FakeRun(controller);
    _run = run;

    Future<void> pump() async {
      try {
        if (generateFailure != null) {
          controller.addError(generateFailure!);
          return;
        }
        var emitted = 0;
        final limit = params.maxTokens < scriptedTokens.length
            ? params.maxTokens
            : scriptedTokens.length;
        for (var i = 0; i < limit; i++) {
          await Future<void>.delayed(tokenDelay);
          if (run.cancelled || controller.isClosed) break;
          controller.add(EngineToken(tokenId: i, text: scriptedTokens[i]));
          emitted++;
        }
        if (!controller.isClosed) {
          final reason = run.cancelled
              ? EngineStopReason.cancelled
              : (emitted >= scriptedTokens.length
                    ? EngineStopReason.endOfSequence
                    : EngineStopReason.maxTokens);
          controller.add(EngineCompletion(reason: reason, tokenCount: emitted));
        }
      } finally {
        if (!controller.isClosed) await controller.close();
        if (identical(_run, run)) _run = null;
      }
    }

    controller.onListen = () => unawaited(pump());
    controller.onCancel = () {
      run.cancelled = true;
    };
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    final run = _run;
    if (run == null) return;
    run.cancelled = true;
    // Let the pump loop observe the flag and emit its terminal event.
    await Future<void>.delayed(tokenDelay + const Duration(milliseconds: 5));
  }

  @override
  Future<void> unload() async {
    final run = _run;
    if (run != null) {
      run.cancelled = true;
      if (!run.controller.isClosed) {
        run.controller.add(
          const EngineCompletion(
            reason: EngineStopReason.cancelled,
            tokenCount: 0,
          ),
        );
        await run.controller.close();
      }
      _run = null;
    }
    if (_loaded) unloadCount++;
    _loaded = false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await unload();
    _disposed = true;
  }
}

class _FakeRun {
  final StreamController<EngineEvent> controller;
  bool cancelled = false;
  _FakeRun(this.controller);
}
