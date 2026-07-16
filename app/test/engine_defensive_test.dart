// QA adversarial pass (Loop 2): checks that don't require the real model or
// native libraries — these paths return before LlamaEngineService ever
// touches an isolate/native symbol, so they run everywhere including CI.

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generate() before load()', () {
    test(
      'errors with a typed EngineFailure via the stream, not a raw throw',
      () async {
        final engine = LlamaEngineService();
        // Single error channel: generate() never throws synchronously; the
        // failure arrives on the stream's onError.
        await expectLater(
          engine.generate(prompt: 'x'),
          emitsError(isA<EngineDisposedFailure>()),
        );
      },
    );
  });

  group('dispose without ever loading', () {
    test(
      'dispose() is idempotent and a disposed engine rejects load()',
      () async {
        final engine = LlamaEngineService();

        await engine.dispose();
        await engine.dispose(); // second call must not throw or hang

        expect(
          () => engine.load('whatever.gguf'),
          throwsA(isA<EngineDisposedFailure>()),
        );
        await expectLater(
          engine.generate(prompt: 'x'),
          emitsError(isA<EngineDisposedFailure>()),
        );
        // cancel() with nothing active/loaded must be a safe no-op.
        await engine.cancel();
      },
    );
  });
}
