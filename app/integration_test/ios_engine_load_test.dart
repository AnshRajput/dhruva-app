// loop/ios-metal-wiring: proves the CocoaPods-vendored llama.xcframework
// (app/ios/Vendor/llama_cpp, wired via app/ios/Podfile) actually dyld-loads
// and runs inference on iOS — not just that `flutter build ios` compiles.
//
// `flutter test` (used by every other *_real_engine_test.dart in test/) runs
// on the HOST (macOS) process, so it can never exercise the iOS build/link
// path. `integration_test` runs the real Flutter engine + app process on the
// target (the iOS Simulator here), which is the only way to prove
// `LlamaEngineService(libraryPath: null)` — providers.dart's exact iOS
// production configuration — resolves `LlamaLibrary.loadFromProcess()`
// against symbols dyld pulled in from the embedded llama.framework.
//
// The iOS Simulator (unlike a real device) runs the app as a native process
// with full host-filesystem access, so this reads the same dev-native SmolLM2
// GGUF the macOS real-engine tests use — no need to bundle/copy a model into
// the simulator's app sandbox for this proof. Real-device Metal verification
// is out of scope (gated on the H4 Apple Developer checkpoint, RISKS.md R2).
//
// Run: flutter test integration_test/ios_engine_load_test.dart -d <sim-udid>

import 'dart:io';

import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _modelPath =
    '/Users/ansh/engineering/dhruva-app/app/.dev-native/models/'
    'SmolLM2-135M-Instruct-Q4_K_M.gguf';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS: real llama.xcframework loads + generates via process '
      'symbols (libraryPath: null)', (tester) async {
    final modelExists = File(_modelPath).existsSync();
    // ignore: avoid_print
    print('DHRUVA IOS PROOF: model present at $_modelPath = $modelExists');
    if (!modelExists) {
      fail(
        'dev-native SmolLM2 GGUF not reachable from the simulator process at '
        '$_modelPath — cannot prove a real model load. (If this is a CI '
        'runner without .dev-native/, that is the expected/documented gap: '
        'this proof only runs on the machine that has the dev-native model.)',
      );
    }

    // Exactly providers.dart's iOS branch: libraryPath: null.
    final engine = LlamaEngineService(libraryPath: null);
    addTearDown(engine.dispose);

    EngineLoadFailure? loadFailure;
    try {
      await engine.load(
        _modelPath,
        params: const EngineLoadParams(contextSize: 512, gpuLayers: 99),
      );
    } on EngineLoadFailure catch (e) {
      loadFailure = e;
    }

    // ignore: avoid_print
    print('DHRUVA IOS PROOF: load() EngineLoadFailure = $loadFailure');
    expect(
      loadFailure,
      isNull,
      reason:
          'engine.load() threw EngineLoadFailure on the iOS Simulator — '
          'the vendored xcframework did not dyld-load from the process',
    );
    expect(engine.isLoaded, isTrue);

    final events = <EngineEvent>[];
    await engine
        .generate(
          messages: const [
            ChatTurn.user(
              'Reply with exactly one word: the capital of '
              'France.',
            ),
          ],
          // Default (non-greedy, temperature 0.7) params — same as
          // production. Greedy decoding on this raw un-templated single-turn
          // prompt sometimes emits EOS immediately for a 135M model, which
          // is a sampling/prompt-shape characteristic, not a wiring signal;
          // this test's job is proving the pipeline runs on iOS, not judging
          // reply quality (chat_controller_real_engine_test.dart already
          // proves coherent replies through the real ChatController+prompt
          // template on macOS).
          params: const EngineGenerateParams(maxTokens: 16),
        )
        .forEach(events.add);

    final text = events.whereType<EngineToken>().map((t) => t.text).join();
    // ignore: avoid_print
    print('DHRUVA IOS PROOF: real generation on iOS Simulator -> "$text"');
    // The proof this test exists for: a real EngineCompletion arrived over
    // the worker-isolate SendPort, meaning the embedded llama.xcframework's
    // dyld-resolved symbols ran a full decode loop on iOS without crashing.
    expect(events.whereType<EngineCompletion>(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
