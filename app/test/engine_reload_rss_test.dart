// Free-path proof (ADR-001): load → unload → reload must not grow RSS
// unboundedly or crash. Skips when native artifacts are absent.
//
// LlamaEngineService runs inference on an isolate we own and, on unload,
// disposes context then model (llama_free / llama_model_free). If that free
// sequence were skipped — as the package's own LlamaEngine does — RSS would
// climb ~one model size (~105MB) per cycle. We assert it stays roughly flat.

import 'dart:io';

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_test_config.dart';

void main() {
  final paths = resolveNativePaths();
  final skip = paths == null
      ? 'native artifacts absent (dylib and/or GGUF)'
      : false;

  test(
    'load/unload/reload does not grow RSS unboundedly',
    () async {
      final engine = LlamaEngineService(libraryPath: paths!.libraryPath);
      const cycles = 4;
      final rss = <int>[];

      for (var i = 0; i < cycles; i++) {
        await engine.load(
          paths.modelPath,
          params: const EngineLoadParams(contextSize: 512, gpuLayers: 0),
        );
        expect(engine.isLoaded, isTrue, reason: 'load failed on cycle $i');

        var n = 0;
        await for (final e in engine.generate(
          prompt: 'Count: one two',
          params: const EngineGenerateParams(maxTokens: 8, greedy: true),
        )) {
          if (e is EngineToken) n++;
        }
        expect(n, greaterThan(0), reason: 'no tokens on cycle $i');

        await engine.unload();
        expect(engine.isLoaded, isFalse);

        final r = ProcessInfo.currentRss;
        rss.add(r);
        // ignore: avoid_print
        print(
          'RSS after cycle $i: ${(r / (1024 * 1024)).toStringAsFixed(1)} MB',
        );
      }

      await engine.dispose();

      // Growth from the first stabilised cycle to the last. With the real free
      // sequence, weights are released each cycle so this stays near zero; a
      // per-cycle leak of the ~105MB model would blow past the ceiling.
      // ponytail: 90MB ceiling (< one model) tolerates allocator fragmentation
      // and Metal residuals on this machine; tighten if it regresses.
      final growth = rss.last - rss[1];
      final growthMb = growth / (1024 * 1024);
      // ignore: avoid_print
      print(
        'RSS growth cycles 1→${cycles - 1}: ${growthMb.toStringAsFixed(1)} MB',
      );
      expect(
        growthMb,
        lessThan(90),
        reason:
            'RSS grew ${growthMb.toStringAsFixed(1)}MB across reloads — '
            'the ctx/model free sequence is not reclaiming native memory',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: skip,
  );
}
