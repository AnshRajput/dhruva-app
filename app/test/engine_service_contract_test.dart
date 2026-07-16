// EngineService contract tests against FakeEngineService (no native code).
// Covers streaming, cancel mid-stream, unload-while-streaming, and the
// EngineFailure taxonomy + mapping (ADR-002).

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as llama;

void main() {
  group('streaming', () {
    test('emits each token then an endOfSequence completion', () async {
      final engine = FakeEngineService(
        scriptedTokens: const ['Hel', 'lo', '!'],
        tokenDelay: const Duration(milliseconds: 1),
      );
      await engine.load('model.gguf');

      final events = await engine.generate(prompt: 'hi').toList();

      final tokens = events.whereType<EngineToken>().toList();
      final done = events.whereType<EngineCompletion>().single;
      expect(tokens.map((t) => t.text).join(), 'Hello!');
      expect(done.reason, EngineStopReason.endOfSequence);
      expect(done.tokenCount, 3);
      // Completion is the last event.
      expect(events.last, isA<EngineCompletion>());
    });

    test('respects maxTokens with a maxTokens completion', () async {
      final engine = FakeEngineService(
        scriptedTokens: const ['a', 'b', 'c', 'd'],
        tokenDelay: const Duration(milliseconds: 1),
      );
      await engine.load('m');

      final events = await engine
          .generate(
            prompt: 'x',
            params: const EngineGenerateParams(maxTokens: 2),
          )
          .toList();

      expect(events.whereType<EngineToken>().length, 2);
      expect(
        events.whereType<EngineCompletion>().single.reason,
        EngineStopReason.maxTokens,
      );
    });

    test(
      'rejects when neither prompt nor messages given (via stream)',
      () async {
        final engine = FakeEngineService();
        await engine.load('m');
        await expectLater(
          engine.generate(),
          emitsError(isA<EngineValidationFailure>()),
        );
      },
    );
  });

  group('cancel', () {
    test(
      'cancel() mid-stream stops early with a cancelled completion',
      () async {
        final engine = FakeEngineService(
          scriptedTokens: const ['1', '2', '3', '4', '5', '6'],
          tokenDelay: const Duration(milliseconds: 15),
        );
        await engine.load('m');

        final seen = <EngineEvent>[];
        final sub = engine.generate(prompt: 'go').listen(seen.add);

        // Let a couple of tokens through, then cancel.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await engine.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await sub.cancel();

        final tokens = seen.whereType<EngineToken>().length;
        expect(tokens, greaterThan(0));
        expect(tokens, lessThan(6));
        expect(
          seen.whereType<EngineCompletion>().last.reason,
          EngineStopReason.cancelled,
        );
      },
    );
  });

  group('unload while streaming', () {
    test('unload terminates the stream and clears isLoaded', () async {
      final engine = FakeEngineService(
        scriptedTokens: const ['a', 'b', 'c', 'd', 'e'],
        tokenDelay: const Duration(milliseconds: 15),
      );
      await engine.load('m');

      final seen = <EngineEvent>[];
      final done = engine
          .generate(prompt: 'go')
          .listen(seen.add)
          .asFuture<void>();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await engine.unload();

      // Stream completes (does not hang) after unload.
      await done.timeout(const Duration(seconds: 1));
      expect(engine.isLoaded, isFalse);
      expect(
        seen.whereType<EngineCompletion>().last.reason,
        EngineStopReason.cancelled,
      );
    });
  });

  group('failure taxonomy', () {
    test('load surfaces the configured typed failure', () async {
      final engine = FakeEngineService(
        loadFailure: const EngineOutOfMemoryFailure('not enough RAM'),
      );
      expect(
        () => engine.load('big.gguf'),
        throwsA(isA<EngineOutOfMemoryFailure>()),
      );
      expect(engine.isLoaded, isFalse);
    });

    test('generate surfaces a decode failure on the stream', () async {
      final engine = FakeEngineService(
        generateFailure: const EngineDecodeFailure('decode blew up'),
      );
      await engine.load('m');
      expect(
        engine.generate(prompt: 'x'),
        emitsError(isA<EngineDecodeFailure>()),
      );
    });

    test(
      'generate before load errors with EngineDisposedFailure (via stream)',
      () async {
        final engine = FakeEngineService();
        await expectLater(
          engine.generate(prompt: 'x'),
          emitsError(isA<EngineDisposedFailure>()),
        );
      },
    );
  });

  // BUG B: empty/whitespace input must be rejected at the service boundary
  // with a typed EngineValidationFailure — before any native/isolate work.
  // Single channel: delivered via the stream's onError, not a sync throw.
  group('empty input validation', () {
    test('fake: empty prompt → EngineValidationFailure', () async {
      final engine = FakeEngineService();
      await engine.load('m');
      await expectLater(
        engine.generate(prompt: ''),
        emitsError(isA<EngineValidationFailure>()),
      );
    });

    test('fake: whitespace-only prompt → EngineValidationFailure', () async {
      final engine = FakeEngineService();
      await engine.load('m');
      await expectLater(
        engine.generate(prompt: '   \n\t '),
        emitsError(isA<EngineValidationFailure>()),
      );
    });

    test('fake: empty messages list → EngineValidationFailure', () async {
      final engine = FakeEngineService();
      await engine.load('m');
      await expectLater(
        engine.generate(messages: const []),
        emitsError(isA<EngineValidationFailure>()),
      );
    });

    test(
      'llama service: empty prompt → EngineValidationFailure without loading '
      '(guard runs before the isolate)',
      () async {
        final engine = LlamaEngineService();
        await expectLater(
          engine.generate(prompt: '  '),
          emitsError(isA<EngineValidationFailure>()),
        );
      },
    );
  });

  group('mapToEngineFailure (llama_cpp_dart → EngineFailure)', () {
    test('model load exception → EngineLoadFailure', () {
      final f = mapToEngineFailure(
        const llama.LlamaModelLoadException('failed to load model foo'),
      );
      expect(f, isA<EngineLoadFailure>());
    });

    test('OOM-ish message on a load exception → EngineOutOfMemoryFailure', () {
      final f = mapToEngineFailure(
        const llama.LlamaModelLoadException('unable to allocate KV buffer'),
      );
      expect(f, isA<EngineOutOfMemoryFailure>());
    });

    test('decode exception → EngineDecodeFailure', () {
      final f = mapToEngineFailure(
        const llama.LlamaDecodeException(1, 'decode failed'),
      );
      expect(f, isA<EngineDecodeFailure>());
    });

    test('library exception (worker error) → EngineLoadFailure', () {
      final f = mapToEngineFailure(
        const llama.LlamaLibraryException('some worker startup error'),
      );
      expect(f, isA<EngineLoadFailure>());
    });

    test('unknown error → EngineUnknownFailure and keeps the cause', () {
      final cause = StateError('weird');
      final f = mapToEngineFailure(cause);
      expect(f, isA<EngineUnknownFailure>());
      expect(f.cause, same(cause));
    });

    test('already-mapped failure is returned unchanged', () {
      const f = EngineDecodeFailure('x');
      expect(mapToEngineFailure(f), same(f));
    });
  });
}
