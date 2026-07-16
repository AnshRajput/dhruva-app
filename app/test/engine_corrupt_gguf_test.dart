// QA adversarial pass (Loop 2): corrupt/garbage GGUF files must not crash the
// native process. A crash here means `flutter test` itself dies — kept in
// its own file so a native abort is isolated to this file's exit code and
// doesn't take the rest of the suite down with it.
//
// Skips when native artifacts are absent (CI has no dylibs/model).

import 'dart:io';
import 'dart:math';

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_test_config.dart';

void main() {
  final paths = resolveNativePaths();
  final skip = paths == null
      ? 'native artifacts absent (dylib and/or GGUF)'
      : false;

  group('corrupt GGUF', () {
    late Directory tmp;
    late String randomPath;
    late String truncatedPath;

    setUpAll(() {
      if (paths == null) return;
      tmp = Directory.systemTemp.createTempSync('dhruva_qa_corrupt_gguf');
      // ~1MB of random bytes: not a GGUF at all.
      final rand = Random(42);
      final bytes = List<int>.generate(1024 * 1024, (_) => rand.nextInt(256));
      randomPath = '${tmp.path}/random_1mb.gguf';
      File(randomPath).writeAsBytesSync(bytes);
      // First 10MB of the real GGUF: valid header, truncated tensor data.
      final real = File(paths.modelPath).readAsBytesSync();
      final cut = real.length > 10 * 1024 * 1024
          ? 10 * 1024 * 1024
          : real.length;
      truncatedPath = '${tmp.path}/truncated_10mb.gguf';
      File(truncatedPath).writeAsBytesSync(real.sublist(0, cut));
    });

    tearDownAll(() {
      if (paths != null) tmp.deleteSync(recursive: true);
    });

    test(
      'random-bytes file fails typed, no crash, service stays usable',
      () async {
        final engine = LlamaEngineService(libraryPath: paths!.libraryPath);
        addTearDown(() => engine.dispose());

        await expectLater(
          () => engine.load(randomPath),
          throwsA(isA<EngineFailure>()),
        ).timeout(const Duration(seconds: 20));
        expect(engine.isLoaded, isFalse);

        // Service must remain usable: a subsequent valid load succeeds.
        await engine.load(
          paths.modelPath,
          params: const EngineLoadParams(contextSize: 512, gpuLayers: 0),
        );
        expect(engine.isLoaded, isTrue);
        var tokens = 0;
        await for (final e in engine.generate(
          prompt: 'Hi',
          params: const EngineGenerateParams(maxTokens: 4, greedy: true),
        )) {
          if (e is EngineToken) tokens++;
        }
        expect(tokens, greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: skip,
    );

    test(
      'truncated real GGUF fails typed, no crash, service stays usable',
      () async {
        final engine = LlamaEngineService(libraryPath: paths!.libraryPath);
        addTearDown(() => engine.dispose());

        await expectLater(
          () => engine.load(truncatedPath),
          throwsA(isA<EngineFailure>()),
        ).timeout(const Duration(seconds: 20));
        expect(engine.isLoaded, isFalse);

        await engine.load(
          paths.modelPath,
          params: const EngineLoadParams(contextSize: 512, gpuLayers: 0),
        );
        expect(engine.isLoaded, isTrue);
        var tokens = 0;
        await for (final e in engine.generate(
          prompt: 'Hi',
          params: const EngineGenerateParams(maxTokens: 4, greedy: true),
        )) {
          if (e is EngineToken) tokens++;
        }
        expect(tokens, greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: skip,
    );
  }, skip: skip);
}
