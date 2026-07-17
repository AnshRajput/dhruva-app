import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/imagine/state/imagine_generation_controller.dart';
import 'package:dhruva/imagine_engine/fake_image_gen_service.dart';
import 'package:dhruva/imagine_engine/image_gen_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late FakeImageGenService fakeImageGen;
  late FakeEngineService fakeEngine;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('imagine_controller_test');
    db = AppDatabase(NativeDatabase.memory());
    fakeImageGen = FakeImageGenService(stepDelay: Duration.zero);
    fakeEngine = FakeEngineService(tokenDelay: Duration.zero);
    container = ProviderContainer(
      overrides: [
        imageGenServiceProvider.overrideWithValue(fakeImageGen),
        engineServiceProvider.overrideWithValue(fakeEngine),
        appDatabaseProvider.overrideWithValue(db),
        generatedImagesDirectoryProvider.overrideWith((ref) async => tempDir),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await tempDir.delete(recursive: true);
  });

  ImagineGenerationController controller() =>
      container.read(imagineGenerationControllerProvider.notifier);

  test('generate streams progress then a persisted result', () async {
    final states = <GenerationState>[];
    container.listen(
      imagineGenerationControllerProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );

    await controller().generate(
      modelPath: '${tempDir.path}/model.safetensors',
      params: const ImageGenParams(prompt: 'a red apple', steps: 3),
    );

    final finalState = container.read(imagineGenerationControllerProvider);
    expect(finalState.phase, GenPhase.done);
    expect(finalState.resultPng, isNotNull);
    expect(finalState.resultWidth, 8);
    expect(states.any((s) => s.phase == GenPhase.loadingModel), isTrue);
    expect(
      states.any((s) => s.phase == GenPhase.generating && s.progressStep == 3),
      isTrue,
    );

    // Persisted to the gallery.
    final rows = await container.read(generatedImageRepositoryProvider).list();
    expect(rows, hasLength(1));
    expect(rows.single.prompt, 'a red apple');
    expect(File(rows.single.filePath).existsSync(), isTrue);
  });

  test('cancel mid-run terminates with GenPhase.cancelled', () async {
    fakeImageGen = FakeImageGenService(
      stepDelay: const Duration(milliseconds: 20),
    );
    container.dispose();
    container = ProviderContainer(
      overrides: [
        imageGenServiceProvider.overrideWithValue(fakeImageGen),
        engineServiceProvider.overrideWithValue(fakeEngine),
        appDatabaseProvider.overrideWithValue(db),
        generatedImagesDirectoryProvider.overrideWith((ref) async => tempDir),
      ],
    );

    final run = controller().generate(
      modelPath: '${tempDir.path}/model.safetensors',
      params: const ImageGenParams(prompt: 'a cat', steps: 10),
    );
    // Let the model "load" and the first progress tick land, then cancel.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await controller().cancel();
    await run;

    expect(
      container.read(imagineGenerationControllerProvider).phase,
      GenPhase.cancelled,
    );
    expect(
      await container.read(generatedImageRepositoryProvider).list(),
      isEmpty,
    );
  });

  test('a state failure (another heavy model resident) surfaces a friendly '
      'error', () async {
    fakeImageGen = FakeImageGenService(
      loadFailure: const ImageGenStateFailure('LLM is loaded'),
    );
    container.dispose();
    container = ProviderContainer(
      overrides: [
        imageGenServiceProvider.overrideWithValue(fakeImageGen),
        engineServiceProvider.overrideWithValue(fakeEngine),
        appDatabaseProvider.overrideWithValue(db),
        generatedImagesDirectoryProvider.overrideWith((ref) async => tempDir),
      ],
    );

    await controller().generate(
      modelPath: '${tempDir.path}/model.safetensors',
      params: const ImageGenParams(prompt: 'a cat'),
    );

    final state = container.read(imagineGenerationControllerProvider);
    expect(state.phase, GenPhase.error);
    expect(state.errorMessage, contains('one big model'));
  });

  test('enhancePrompt rewrites via the loaded engine', () async {
    fakeEngine = FakeEngineService(
      scriptedTokens: const ['a ', 'vivid ', 'sunset'],
      tokenDelay: Duration.zero,
    );
    await fakeEngine.load('any.gguf');
    container.dispose();
    container = ProviderContainer(
      overrides: [
        imageGenServiceProvider.overrideWithValue(fakeImageGen),
        engineServiceProvider.overrideWithValue(fakeEngine),
        appDatabaseProvider.overrideWithValue(db),
        generatedImagesDirectoryProvider.overrideWith((ref) async => tempDir),
      ],
    );

    final result = await controller().enhancePrompt('a sunset');
    expect(result, 'a vivid sunset');
  });

  test('enhancePrompt returns null when no engine is loaded', () async {
    // fakeEngine here is fresh (unloaded) by default from setUp.
    final result = await controller().enhancePrompt('a sunset');
    expect(result, isNull);
  });
}
