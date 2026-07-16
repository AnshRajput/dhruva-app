// Real-model integration smoke test (macOS build machine). Skips when the
// dylib or GGUF is absent, so CI stays green without native artifacts.
//
// Proves, on the real engine: load succeeds, a completion streams >5 tokens,
// cancel stops within 500ms, unload frees, and reload works.
//
// Runs CPU-only (gpuLayers: 0) for determinism and to avoid repeated Metal
// pipeline compilation; Metal is exercised separately (see the loop report).

import 'dart:async';

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_test_config.dart';

void main() {
  final paths = resolveNativePaths();
  final skip = paths == null
      ? 'native artifacts absent (dylib and/or GGUF)'
      : false;

  group('real SmolLM2 engine', () {
    late LlamaEngineService engine;

    setUp(() {
      engine = LlamaEngineService(libraryPath: paths!.libraryPath);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test(
      'load → stream >5 tokens → cancel <500ms → unload → reload',
      () async {
        // --- load ---
        await engine.load(
          paths!.modelPath,
          params: const EngineLoadParams(contextSize: 512, gpuLayers: 0),
        );
        expect(engine.isLoaded, isTrue);

        // --- stream a completion, capture the first ~20 tokens ---
        final firstTokens = <String>[];
        var count = 0;
        EngineStopReason? reason;
        await for (final e in engine.generate(
          prompt: 'The capital of France is',
          params: const EngineGenerateParams(maxTokens: 24, greedy: true),
        )) {
          switch (e) {
            case EngineToken():
              count++;
              if (firstTokens.length < 20) firstTokens.add(e.text);
            case EngineCompletion():
              reason = e.reason;
          }
        }
        // Surfaced in test output for the loop report.
        // ignore: avoid_print
        print('SMOKE first tokens => "${firstTokens.join()}"');
        expect(count, greaterThan(5));
        expect(reason, isNotNull);

        // --- cancel must stop within 500ms ---
        final sw = Stopwatch()..start();
        final gotFirst = Completer<void>();
        late StreamSubscription<EngineEvent> sub;
        final ended = Completer<void>();
        sub = engine
            .generate(
              prompt: 'Write a very long essay about the ocean, in detail:',
              params: const EngineGenerateParams(maxTokens: 4096),
            )
            .listen(
              (e) {
                if (e is EngineToken && !gotFirst.isCompleted) {
                  gotFirst.complete();
                }
                if (e is EngineCompletion && !ended.isCompleted) {
                  ended.complete();
                }
              },
              onDone: () {
                if (!ended.isCompleted) ended.complete();
              },
            );
        await gotFirst.future; // generation is genuinely underway
        final cancelStart = Stopwatch()..start();
        await engine.cancel();
        await ended.future.timeout(const Duration(seconds: 2));
        cancelStart.stop();
        await sub.cancel();
        sw.stop();
        expect(
          cancelStart.elapsedMilliseconds,
          lessThan(500),
          reason: 'cancel took ${cancelStart.elapsedMilliseconds}ms',
        );

        // --- unload frees ---
        await engine.unload();
        expect(engine.isLoaded, isFalse);
        expect(
          () => engine.generate(prompt: 'x'),
          throwsA(isA<EngineDisposedFailure>()),
        );

        // --- reload works ---
        await engine.load(
          paths.modelPath,
          params: const EngineLoadParams(contextSize: 512, gpuLayers: 0),
        );
        expect(engine.isLoaded, isTrue);
        var reloadCount = 0;
        await for (final e in engine.generate(
          prompt: 'Hello',
          params: const EngineGenerateParams(maxTokens: 8, greedy: true),
        )) {
          if (e is EngineToken) reloadCount++;
        }
        expect(reloadCount, greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }, skip: skip);
}
