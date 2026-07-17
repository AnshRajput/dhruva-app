// Vision free-path proof (Loop 7, D4): load vision model + mmproj -> run an
// image generate -> unload -> reload, repeatedly. The projector (mtmd) is
// disposed before ctx/model on unload; if it leaked, RSS would climb ~one
// mmproj (~104MB) per cycle. We assert it stays roughly flat. Skips when the
// SmolVLM artifacts are absent.

import 'dart:io';

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_test_config.dart';

void main() {
  final v = resolveVisionPaths();
  final skip = v == null
      ? 'vision artifacts absent (dylib/model/mmproj)'
      : false;

  test(
    'vision load/unload/reload does not grow RSS unboundedly',
    () async {
      final engine = LlamaEngineService(libraryPath: v!.libraryPath);
      addTearDown(() => engine.dispose());
      final imageBytes = await File('test/assets/red_64.png').readAsBytes();
      const cycles = 4;
      final rss = <int>[];

      for (var i = 0; i < cycles; i++) {
        await engine.load(
          v.modelPath,
          params: EngineLoadParams(
            contextSize: 2048,
            gpuLayers: 99,
            mmprojPath: v.mmprojPath,
          ),
        );
        expect(engine.isMultimodal, isTrue, reason: 'no mmproj on cycle $i');

        var n = 0;
        await for (final e in engine.generate(
          messages: [
            ChatTurn.user('Name the color.', images: [imageBytes]),
          ],
          params: const EngineGenerateParams(maxTokens: 12, greedy: true),
        )) {
          if (e is EngineToken) n++;
        }
        expect(n, greaterThan(0), reason: 'no tokens on cycle $i');

        await engine.unload();
        expect(engine.isLoaded, isFalse);
        expect(engine.isMultimodal, isFalse);

        final r = ProcessInfo.currentRss;
        rss.add(r);
        // ignore: avoid_print
        print(
          'vision RSS after cycle $i: '
          '${(r / (1024 * 1024)).toStringAsFixed(1)} MB',
        );
      }

      // Growth from the first stabilised cycle to the last. With mtmd/ctx/model
      // all freed each cycle this stays near zero; a leaked projector (~104MB)
      // per cycle would blow past the ceiling.
      final growthMb = (rss.last - rss[1]) / (1024 * 1024);
      // ignore: avoid_print
      print(
        'vision RSS growth cycles 1->${cycles - 1}: '
        '${growthMb.toStringAsFixed(1)} MB',
      );
      // ponytail: 150MB ceiling (< one model+mmproj) tolerates allocator
      // fragmentation + Metal residuals; tighten if it regresses.
      expect(
        growthMb,
        lessThan(150),
        reason:
            'vision RSS grew ${growthMb.toStringAsFixed(1)}MB across reloads — '
            'the mtmd/ctx/model free sequence is not reclaiming native memory',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: skip,
  );
}
