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

  /// Tokens emitted when a [generate] turn carries images (and this fake is
  /// [multimodal]). Joined they form a canned vision answer that references
  /// the image, so UI/vision tests exercise the attach → answer flow without
  /// native code.
  final List<String> visionTokens;

  /// Delay between tokens; also the cooperative-cancel checkpoint interval.
  final Duration tokenDelay;

  /// When set, [load] throws this instead of loading.
  final EngineFailure? loadFailure;

  /// When set, [generate]'s stream emits this error instead of tokens.
  final EngineFailure? generateFailure;

  /// When true, a successful [load] reports [isMultimodal] and image turns
  /// stream [visionTokens]. Models the vision-capable model in UI tests.
  final bool multimodal;

  FakeEngineService({
    this.scriptedTokens = const ['Hello', ' ', 'world', '!'],
    this.visionTokens = const ['I ', 'see ', 'a ', 'red ', 'image', '.'],
    this.tokenDelay = const Duration(milliseconds: 10),
    this.loadFailure,
    this.generateFailure,
    this.multimodal = false,
  });

  bool _loaded = false;
  bool _disposed = false;
  _FakeRun? _run;

  /// Test hook: number of successful [load] calls.
  int loadCount = 0;

  /// Test hook: number of [unload] calls.
  int unloadCount = 0;

  /// Test hook: the `messages` passed to the most recent [generate] call —
  /// lets a test assert what actually reached the "engine" (e.g. a
  /// character's persona system prompt), not just what the caller intended
  /// to send.
  List<ChatTurn>? lastMessages;

  /// Test hook: the `params` passed to the most recent [generate] call.
  EngineGenerateParams? lastParams;

  /// Test hook: number of images across the messages of the most recent
  /// [generate] call.
  int lastImageCount = 0;

  @override
  bool get isLoaded => _loaded && !_disposed;

  @override
  bool get isMultimodal => isLoaded && multimodal;

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
    lastMessages = messages;
    lastParams = params;
    lastImageCount = messages?.fold<int>(0, (n, m) => n + m.images.length) ?? 0;
    // Image turns on a multimodal fake stream the canned vision answer.
    final tokens = (multimodal && lastImageCount > 0)
        ? visionTokens
        : scriptedTokens;
    // Single error channel (see EngineService.generate): never throw; surface
    // every pre-flight failure via the returned stream's onError.
    final preflight =
        checkGenerateArgs(prompt, messages) ??
        (!isLoaded
            ? const EngineDisposedFailure('no model loaded; call load() first')
            : null) ??
        (_run != null
            ? const EngineStateFailure('a generation is already in flight')
            : null);
    if (preflight != null) return Stream<EngineEvent>.error(preflight);

    final controller = StreamController<EngineEvent>();
    final run = _FakeRun(controller);
    _run = run;

    Future<void> pump() async {
      final sw = Stopwatch()..start();
      try {
        if (generateFailure != null) {
          controller.addError(generateFailure!);
          return;
        }
        var emitted = 0;
        final limit = params.maxTokens < tokens.length
            ? params.maxTokens
            : tokens.length;
        for (var i = 0; i < limit; i++) {
          await Future<void>.delayed(tokenDelay);
          if (run.cancelled || controller.isClosed) break;
          controller.add(EngineToken(tokenId: i, text: tokens[i]));
          emitted++;
        }
        if (!controller.isClosed) {
          final reason = run.cancelled
              ? EngineStopReason.cancelled
              : (emitted >= tokens.length
                    ? EngineStopReason.endOfSequence
                    : EngineStopReason.maxTokens);
          controller.add(
            EngineCompletion(
              reason: reason,
              tokenCount: emitted,
              elapsedMs: sw.elapsedMilliseconds,
            ),
          );
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
