// Android twin of ios_engine_load_test.dart: proves the bundled
// llama-cpp-dart.aar (.so files) dlopen()s and generates on a real arm64
// Android runtime. Guards the 16 KB page-size rebuild
// (scripts/build-android-aar.sh) against an ABI break.
//
// Setup: adb push SmolLM2-135M-Instruct-Q4_K_M.gguf /data/local/tmp/
// Run:   flutter test integration_test/android_engine_load_test.dart -d <id>
import 'dart:io';

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _modelPath = '/data/local/tmp/SmolLM2-135M-Instruct-Q4_K_M.gguf';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android: bundled llama .so loads + generates',
    (tester) async {
      expect(
        File(_modelPath).existsSync(),
        isTrue,
        reason: 'adb push the SmolLM2 GGUF to $_modelPath first',
      );

      final engine = LlamaEngineService(libraryPath: 'libllama.so');
      addTearDown(engine.dispose);
      await engine.load(
        _modelPath,
        params: const EngineLoadParams(contextSize: 512),
      );
      expect(engine.isLoaded, isTrue);

      final events = <EngineEvent>[];
      await engine
          .generate(
            messages: const [
              ChatTurn.user(
                'Reply with exactly one word: the capital of France.',
              ),
            ],
            params: const EngineGenerateParams(maxTokens: 16),
          )
          .forEach(events.add);

      final text = events.whereType<EngineToken>().map((t) => t.text).join();
      // ignore: avoid_print
      print('DHRUVA ANDROID PROOF: "$text"');
      expect(events.whereType<EngineCompletion>(), isNotEmpty);
      expect(text.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
