// A/B: same model + prompt with Metal offload (gpuLayers 99) vs CPU only (0).
// Isolates whether garbled output on iOS comes from the Metal backend.
// Run: flutter test integration_test/ios_gpu_cpu_ab_test.dart -d <sim>
//        --dart-define=AB_MODEL=/abs/path/model.gguf
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _model = String.fromEnvironment('AB_MODEL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final layers in [0, 99]) {
    testWidgets('gpuLayers=$layers', (tester) async {
      final engine = LlamaEngineService();
      addTearDown(engine.dispose);
      await engine.load(
        _model,
        params: EngineLoadParams(contextSize: 512, gpuLayers: layers),
      );
      final events = <EngineEvent>[];
      await engine
          .generate(
            messages: const [
              ChatTurn.user('What is the capital of France? One sentence.'),
            ],
            params: const EngineGenerateParams(maxTokens: 24),
          )
          .forEach(events.add);
      final text = events.whereType<EngineToken>().map((t) => t.text).join();
      // ignore: avoid_print
      print('AB gpuLayers=$layers -> "$text"');
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
