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
        // Single error channel: post-unload generate errors via the stream.
        await expectLater(
          engine.generate(prompt: 'x'),
          emitsError(isA<EngineDisposedFailure>()),
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

    // Loop 4 D3: a genuine 2-turn conversation over the messages/ChatTemplate
    // path — system prompt + prior turns fed back in — where turn 2 can only be
    // answered from turn 1's context.
    test(
      'multi-turn: system prompt + history; turn 2 references turn 1',
      () async {
        await engine.load(
          paths!.modelPath,
          params: const EngineLoadParams(contextSize: 1024, gpuLayers: 0),
        );

        Future<String> ask(List<ChatTurn> messages) async {
          final buf = StringBuffer();
          await for (final e in engine.generate(
            messages: messages,
            params: const EngineGenerateParams(maxTokens: 48, greedy: true),
          )) {
            if (e is EngineToken) buf.write(e.text);
          }
          return buf.toString();
        }

        const system = ChatTurn.system(
          'You are a helpful assistant. Answer briefly.',
        );
        // Turn 1 establishes the name; turn 2's question contains NO name, so a
        // correct answer can only come from the history (proves the template
        // path threads prior turns, not just the latest message).
        const user1 = ChatTurn.user('My name is Max. Say hi to me.');

        final reply1 = await ask(const [system, user1]);
        expect(reply1.trim(), isNotEmpty, reason: 'turn 1 produced no text');

        // Turn 2 carries the full history (system + user1 + assistant + user2).
        final turn2 = await ask([
          system,
          user1,
          ChatTurn.assistant(reply1),
          const ChatTurn.user('What is my name?'),
        ]);
        // ignore: avoid_print
        print('MULTITURN turn-2 => "$turn2"');
        expect(
          turn2.toLowerCase(),
          contains('max'),
          reason: 'turn 2 did not recall the name from turn 1',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // Loop 4 D4: seed reaches the native sampler. With temperature>0 a fixed
    // seed makes generation reproducible; the two runs must match token-for-
    // token. (Without seed plumbing each run gets a random seed and diverges.)
    test(
      'seed reaches the sampler: fixed seed → reproducible output',
      () async {
        await engine.load(
          paths!.modelPath,
          params: const EngineLoadParams(contextSize: 512, gpuLayers: 0),
        );

        Future<List<int>> run() async {
          final ids = <int>[];
          await for (final e in engine.generate(
            prompt: 'List three animals:',
            params: const EngineGenerateParams(
              maxTokens: 24,
              temperature: 0.9,
              topK: 60,
              topP: 0.95,
              seed: 424242,
            ),
          )) {
            if (e is EngineToken) ids.add(e.tokenId);
          }
          return ids;
        }

        final a = await run();
        final b = await run();
        expect(a, isNotEmpty);
        expect(
          b,
          equals(a),
          reason: 'same seed must reproduce the same tokens',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // Loop 4 D1: load's ready.future timeout. A 1ms ceiling fires long before
    // native init can signal ready, proving load() gives up with a typed
    // EngineLoadFailure instead of hanging forever.
    test(
      'load times out with EngineLoadFailure when ready never arrives',
      () async {
        final slow = LlamaEngineService(
          libraryPath: paths!.libraryPath,
          loadTimeout: const Duration(milliseconds: 1),
        );
        await expectLater(
          () => slow.load(
            paths.modelPath,
            params: const EngineLoadParams(contextSize: 512, gpuLayers: 0),
          ),
          throwsA(isA<EngineLoadFailure>()),
        );
        expect(slow.isLoaded, isFalse);
        await slow.dispose();
      },
    );
  }, skip: skip);
}
