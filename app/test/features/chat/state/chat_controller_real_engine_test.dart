// MVP-journey smoke test (macOS build machine, real engine): the exact path
// chat-spec.md's [G1] exit gate names — pick an installed model, send a
// message, get a streamed reply — driven through the real `ChatController`
// + real `LlamaEngineService` + real SmolLM2 GGUF, not `FakeEngineService`.
// Skips when the dev-native dylib/GGUF are absent (see native_test_config.
// dart), so CI stays green without them, matching engine_smoke_test.dart's
// existing pattern.

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart'
    show AppDatabase, InstalledModelsCompanion, MessageStatus;
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../native_test_config.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  final paths = resolveNativePaths();
  final skip = paths == null
      ? 'native artifacts absent (dylib and/or GGUF)'
      : false;

  test(
    'MVP journey: real engine, real SmolLM2, a full chat turn through ChatController',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final engine = LlamaEngineService(libraryPath: paths!.libraryPath);
      addTearDown(engine.dispose);

      final modelId = await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'local/SmolLM2-135M-Instruct',
              fileName: 'SmolLM2-135M-Instruct-Q4_K_M.gguf',
              sizeBytes: File(paths.modelPath).lengthSync(),
              localPath: paths.modelPath,
              downloadedAt: DateTime.now(),
            ),
          );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          engineServiceProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(container.dispose);

      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      final notifier = container.read(chatControllerProvider(args).notifier);

      await notifier.sendMessage(
        'What is the capital of France? Answer in one short sentence.',
      );

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.modelLoadError, isNull);
      final assistant = state.messages.last;
      // Surfaced in test output for the Loop-4 report's MVP-smoke evidence.
      // ignore: avoid_print
      print(
        'MVP SMOKE: user asked "What is the capital of France? Answer in '
        'one short sentence." -> model said: "${assistant.content}"',
      );
      expect(assistant.content.trim(), isNotEmpty);
      expect(assistant.status, MessageStatus.complete);
      expect(assistant.tokCount, greaterThan(0));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
