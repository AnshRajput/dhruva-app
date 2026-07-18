// Playground + AI news widget tests (VIDEO_FIXES.md P2 #7; PlaygroundMock).
// Covers: two-model compare renders + runs through the fake engine, the
// Temperature slider updates controller state, the <2-installed empty states,
// and the opt-in AI-news digest (load / empty / error).

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/playground/state/playground_controller.dart';
import 'package:dhruva/features/playground/state/playground_installed_models_provider.dart';
import 'package:dhruva/features/playground/ui/playground_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/mock_hf_client.dart';

InstalledModelInfo _model(int id, String repoId, String file) =>
    InstalledModelInfo(
      id: id,
      repoId: repoId,
      fileName: file,
      quant: 'Q4_K_M',
      sizeBytes: 1000,
      localPath: '/tmp/$file',
      gated: false,
      downloadedAt: DateTime(2026, 7, 18),
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  // Tall surface so the whole compare column (cards → sliders → result
  // columns) is built by the lazy ListView; on a real phone this scrolls.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const PlaygroundScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final twoModels = [
    _model(1, 'unsloth/Llama-3.2-1B-Instruct-GGUF', 'llama.gguf'),
    _model(2, 'Qwen/Qwen2.5-1.5B-Instruct-GGUF', 'qwen.gguf'),
  ];

  Override installed(List<InstalledModelInfo> models) =>
      playgroundInstalledModelsProvider.overrideWith((ref) async => models);

  Override hf(MockClient client) =>
      hfApiClientProvider.overrideWithValue(mockHfClient(client));

  group('Playground compare', () {
    testWidgets('renders two model columns, prompt, run, sliders', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: [
          installed(twoModels),
          hf(MockClient((_) async => http.Response('[]', 200))),
        ],
      );

      // One-line value explainer is present.
      expect(find.textContaining('One prompt, two models'), findsOneWidget);
      // Both models named (model cards). At least one occurrence each.
      expect(find.textContaining('Llama-3.2-1B-Instruct'), findsWidgets);
      expect(find.textContaining('Qwen2.5-1.5B-Instruct'), findsWidgets);
      expect(find.text('Run on both'), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(3));
      // No winner badge before a run.
      expect(find.text('Fastest'), findsNothing);
    });

    testWidgets('runs one prompt through BOTH models', (tester) async {
      final container = await _pump(
        tester,
        overrides: [
          installed(twoModels),
          hf(MockClient((_) async => http.Response('[]', 200))),
          engineServiceProvider.overrideWithValue(
            FakeEngineService(scriptedTokens: const ['Hi', ' ', 'there']),
          ),
        ],
      );

      await tester.enterText(find.byType(TextField), 'Say hi');
      await tester.tap(find.text('Run on both'));
      await tester.pumpAndSettle();

      // Both columns produced the fake reply and finished.
      expect(find.text('Hi there'), findsNWidgets(2));
      expect(find.textContaining('done'), findsNWidgets(2));
      // Winner-ish framing: exactly one column is marked fastest once both done.
      expect(find.text('Fastest'), findsOneWidget);
      final state = container.read(playgroundControllerProvider);
      expect(state.isRunning, isFalse);
      expect(state.runA.status, RunStatus.done);
      expect(state.runB.status, RunStatus.done);
    });

    testWidgets('the not-yet-started column reads "queued", never idle Ready', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: [
          installed(twoModels),
          hf(MockClient((_) async => http.Response('[]', 200))),
          engineServiceProvider.overrideWithValue(
            FakeEngineService(scriptedTokens: const ['Hi']),
          ),
        ],
      );

      await tester.enterText(find.byType(TextField), 'Say hi');
      await tester.tap(find.text('Run on both'));
      // One frame: model A is loading, model B waits its turn (not "Ready").
      await tester.pump();
      expect(find.text('Waiting its turn…'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('swapping a model after a run clears its stale result + badge', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        overrides: [
          installed(twoModels),
          hf(MockClient((_) async => http.Response('[]', 200))),
          engineServiceProvider.overrideWithValue(
            FakeEngineService(scriptedTokens: const ['Hi', ' ', 'there']),
          ),
        ],
      );

      await tester.enterText(find.byType(TextField), 'Say hi');
      await tester.tap(find.text('Run on both'));
      await tester.pumpAndSettle();
      expect(find.text('Fastest'), findsOneWidget);

      // Re-selecting model A must drop A's stale output + the (now wrong) badge.
      container.read(playgroundControllerProvider.notifier).setModelA(2);
      await tester.pumpAndSettle();

      final state = container.read(playgroundControllerProvider);
      expect(state.runA.status, RunStatus.idle);
      expect(state.runA.text, isEmpty);
      expect(find.text('Fastest'), findsNothing);
      // The other column keeps its finished result.
      expect(state.runB.status, RunStatus.done);
    });

    testWidgets('Temperature slider updates controller state', (tester) async {
      final container = await _pump(
        tester,
        overrides: [
          installed(twoModels),
          hf(MockClient((_) async => http.Response('[]', 200))),
        ],
      );

      expect(container.read(playgroundControllerProvider).temperature, 0.8);
      await tester.drag(find.byType(Slider).first, const Offset(-120, 0));
      await tester.pump();
      expect(
        container.read(playgroundControllerProvider).temperature,
        lessThan(0.8),
      );
    });
  });

  group('Playground empty states', () {
    testWidgets('zero models prompts to install two', (tester) async {
      await _pump(
        tester,
        overrides: [
          installed(const []),
          hf(MockClient((_) async => http.Response('[]', 200))),
        ],
      );
      expect(find.textContaining('at least'), findsOneWidget);
      expect(find.text('Browse models'), findsOneWidget);
    });

    testWidgets('one model prompts to add one more', (tester) async {
      await _pump(
        tester,
        overrides: [
          installed([twoModels.first]),
          hf(MockClient((_) async => http.Response('[]', 200))),
        ],
      );
      expect(find.textContaining('one more'), findsOneWidget);
    });
  });

  group('AI news digest (opt-in)', () {
    const digestJson =
        '[{"id":"unsloth/Qwen2.5-0.5B-Instruct-GGUF","likes":9,"downloads":5000,"tags":["gguf"]},'
        '{"id":"TheBloke/TinyLlama-1.1B-Chat-GGUF","likes":8,"downloads":3000,"tags":["gguf"]},'
        '{"id":"meta/Llama-3-8B-Instruct-GGUF","likes":99,"downloads":900000,"tags":["gguf"]}]';

    testWidgets('does not fetch until the user taps Load, then shows items', (
      tester,
    ) async {
      var calls = 0;
      await _pump(
        tester,
        overrides: [
          installed(const []),
          hf(
            MockClient((_) async {
              calls++;
              return http.Response(digestJson, 200);
            }),
          ),
        ],
      );

      await tester.tap(find.text('AI news'));
      await tester.pumpAndSettle();

      // Opt-in: card present, nothing fetched yet.
      expect(find.text('This week in on-device AI'), findsOneWidget);
      expect(find.text('Load'), findsOneWidget);
      expect(calls, 0);

      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      // Sub-2B filtered in, the 8B filtered out.
      expect(find.textContaining('2 sub-2B'), findsOneWidget);
      expect(find.textContaining('TinyLlama-1.1B-Chat'), findsOneWidget);
      expect(find.textContaining('Llama-3-8B'), findsNothing);
    });

    testWidgets('empty digest when nothing is sub-2B', (tester) async {
      await _pump(
        tester,
        overrides: [
          installed(const []),
          hf(
            MockClient(
              (_) async => http.Response(
                '[{"id":"meta/Llama-3-8B-GGUF","likes":1,"downloads":1,"tags":["gguf"]}]',
                200,
              ),
            ),
          ),
        ],
      );
      await tester.tap(find.text('AI news'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No sub-2B releases'), findsOneWidget);
    });

    testWidgets('surfaces an error with retry', (tester) async {
      await _pump(
        tester,
        overrides: [
          installed(const []),
          hf(MockClient((_) async => http.Response('nope', 500))),
        ],
      );
      await tester.tap(find.text('AI news'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not reach Hugging Face'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
