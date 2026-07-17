// Real multimodal round-trip (Loop 7, gate G1): load a vision model + its
// mmproj projector via libmtmd, feed a known solid-red 64x64 PNG plus a
// question, and assert the model produces a non-empty answer that references
// the image. Skips when the SmolVLM artifacts / dylib are absent.
//
// Also documents the "vision model without projector loads text-only"
// decision and proves the isMultimodal capability signal.
//
// QA (Loop-7 TEST, attack 1): two more non-vacuous real-model checks below —
// (a) a DIFFERENT image (solid blue, generated at test time via dart:ui,
// same technique image_downscale_test.dart already uses so no binary
// fixture is needed) gets a different/appropriate answer, not the same
// canned-looking string as the red one, proving G1 isn't a fluke/hardcoded
// match; (b) a PNG with a rendered word on it, run through the app's own
// "extract text" preset prompt, to sanity-check OCR-ish capability on a
// small vision model.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_test_config.dart';

Future<Uint8List> _solidPng(int width, int height, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

// QA: a word rendered via dart:ui's own ParagraphBuilder inside `flutter
// test` does NOT reliably produce legible glyphs — the headless test
// environment has no real font loaded, so text painted this way came out
// as a solid black bar (confirmed by dumping the PNG and looking at it),
// not readable "CAT". `test/assets/word_cat.png` is a committed fixture
// instead (rendered with Pillow + a real system font, same generating
// approach as `exif_rotated.jpg`/`animated.gif`) so the OCR check below
// exercises the model against genuinely legible text, not a Flutter test-
// harness artifact.

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

  test(
    'QA attack 1: a DIFFERENT image gets a different/appropriate answer — '
    'not the same canned-looking string as the red image above (non-vacuous '
    'G1: proves the model is actually looking at pixels, not returning a '
    'fixed reply regardless of input)',
    () async {
      final engine = LlamaEngineService(libraryPath: v!.libraryPath);
      addTearDown(() => engine.dispose());
      await engine.load(
        v.modelPath,
        params: EngineLoadParams(contextSize: 4096, mmprojPath: v.mmprojPath),
      );

      final blue = await _solidPng(64, 64, const ui.Color(0xFF0000FF));
      final buffer = StringBuffer();
      await for (final e in engine.generate(
        messages: [
          ChatTurn.user(
            'What is the main color of this image? Answer in one short '
            'sentence.',
            images: [blue],
          ),
        ],
        params: const EngineGenerateParams(maxTokens: 64, greedy: true),
      )) {
        if (e is EngineToken) buffer.write(e.text);
      }

      final answer = buffer.toString().trim();
      // ignore: avoid_print
      print('VISION ANSWER (solid blue): "$answer"');
      expect(answer, isNotEmpty);
      expect(
        answer.toLowerCase(),
        isNot(contains('red')),
        reason:
            'a blue image answered "red" — either a canned reply or the '
            'model is not actually conditioning on the image: "$answer"',
      );
      expect(
        answer.toLowerCase(),
        contains('blue'),
        reason: 'answer did not reference the blue image: "$answer"',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: skip,
  );

  test(
    'QA attack 1: an image with a rendered WORD, run through the extract-'
    'text preset prompt (vision_presets.dart\'s extractTextPrompt), returns '
    'text containing that word — OCR-ish capability on a small vision '
    'model. Best-effort: SmolVLM-500M is a 500M model, not a dedicated OCR '
    'engine, so this checks the exact preset prompt actually in production '
    '(vision_presets.dart) produces a recognizable, non-empty, on-topic '
    'reply rather than demanding perfect character-for-character OCR.',
    () async {
      final engine = LlamaEngineService(libraryPath: v!.libraryPath);
      addTearDown(() => engine.dispose());
      await engine.load(
        v.modelPath,
        params: EngineLoadParams(contextSize: 4096, mmprojPath: v.mmprojPath),
      );

      final word = await File('test/assets/word_cat.png').readAsBytes();
      final buffer = StringBuffer();
      await for (final e in engine.generate(
        messages: [
          ChatTurn.user(
            // Exact string composer.dart's "Extract text" quick action
            // sends — vision_presets.dart's extractTextPrompt, inlined here
            // (this is engine_bindings/-scoped; importing features/chat
            // would cross ADR-002's dependency direction the wrong way).
            'Extract all text from this image, output only the text',
            images: [word],
          ),
        ],
        params: const EngineGenerateParams(maxTokens: 32, greedy: true),
      )) {
        if (e is EngineToken) buffer.write(e.text);
      }

      final answer = buffer.toString().trim();
      // ignore: avoid_print
      print('VISION OCR ANSWER (word "CAT"): "$answer"');
      expect(answer, isNotEmpty, reason: 'model returned no text at all');
      expect(
        answer.toUpperCase(),
        contains('CAT'),
        reason:
            'model did not read back the word "CAT" from the image: '
            '"$answer" — a small model may genuinely be too weak for this; '
            'if it reliably fails, downgrade the extract-text feature\'s '
            'promise in the UI/README rather than treating this as a hard '
            'gate',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: skip,
  );
}
