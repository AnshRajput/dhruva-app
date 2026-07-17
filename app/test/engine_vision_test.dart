// Real multimodal round-trip (Loop 7, gate G1): load a vision model + its
// mmproj projector via libmtmd, feed a known solid-red 64x64 PNG plus a
// question, and assert the model produces a non-empty answer that references
// the image. Skips when the SmolVLM artifacts / dylib are absent.
//
// Also documents the "vision model without projector loads text-only"
// decision and proves the isMultimodal capability signal.

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

  // The image bytes live beside the test; the red PNG is committed.
  final redPng = File('test/assets/red_64.png');

  test(
    'vision model + mmproj: image -> question -> grounded answer (G1)',
    () async {
      final engine = LlamaEngineService(libraryPath: v!.libraryPath);
      addTearDown(() => engine.dispose());

      await engine.load(
        v.modelPath,
        params: EngineLoadParams(
          contextSize: 4096,
          gpuLayers: 99,
          mmprojPath: v.mmprojPath,
        ),
      );
      expect(engine.isLoaded, isTrue);
      // D3: projector loaded -> capability signal is on.
      expect(
        engine.isMultimodal,
        isTrue,
        reason: 'mmproj loaded but isMultimodal is false',
      );

      final imageBytes = await redPng.readAsBytes();
      final buffer = StringBuffer();
      await for (final e in engine.generate(
        messages: [
          ChatTurn.user(
            'What is the main color of this image? Answer in one short '
            'sentence.',
            images: [imageBytes],
          ),
        ],
        params: const EngineGenerateParams(maxTokens: 64, greedy: true),
      )) {
        if (e is EngineToken) buffer.write(e.text);
      }

      final answer = buffer.toString().trim();
      // ignore: avoid_print
      print('VISION ANSWER (red_64.png): "$answer"');
      expect(answer, isNotEmpty, reason: 'model returned no text for image QA');
      // Grounded: the answer should mention the colour it was shown.
      expect(
        answer.toLowerCase(),
        contains('red'),
        reason: 'answer did not reference the red image: "$answer"',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: skip,
  );

  test(
    'vision model loaded without mmproj is text-only (isMultimodal false)',
    () async {
      final engine = LlamaEngineService(libraryPath: v!.libraryPath);
      addTearDown(() => engine.dispose());

      // Same GGUF, no projector -> loads, runs text, image gate stays closed.
      await engine.load(
        v.modelPath,
        params: const EngineLoadParams(contextSize: 1024, gpuLayers: 99),
      );
      expect(engine.isLoaded, isTrue);
      expect(engine.isMultimodal, isFalse);

      var tokens = 0;
      await for (final e in engine.generate(
        prompt: 'Hello',
        params: const EngineGenerateParams(maxTokens: 8, greedy: true),
      )) {
        if (e is EngineToken) tokens++;
      }
      expect(tokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: skip,
  );
}
