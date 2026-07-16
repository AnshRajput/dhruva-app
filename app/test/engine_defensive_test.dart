// QA adversarial pass (Loop 2): checks that don't require the real model or
// native libraries — these paths return before LlamaEngineService ever
// touches an isolate/native symbol, so they run everywhere including CI.

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generate() before load()', () {
    test('throws a typed EngineFailure, not a raw exception', () {
      final engine = LlamaEngineService();
      expect(
        () => engine.generate(prompt: 'x'),
        throwsA(isA<EngineDisposedFailure>()),
      );
    });
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
        expect(
          () => engine.generate(prompt: 'x'),
          throwsA(isA<EngineDisposedFailure>()),
        );
        // cancel() with nothing active/loaded must be a safe no-op.
        await engine.cancel();
      },
    );
  });
}
