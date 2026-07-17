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
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart'
    show AppDatabase, InstalledModelsCompanion, MessageRole, MessageStatus;
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

  // QA (Loop-4 attack list #1): the same real-engine journey, but proving
  // history survives a genuine "app restart" — a fresh AppDatabase reopened
  // on the SAME on-disk file (not a shared in-memory connection) plus a
  // brand-new ChatController/ProviderContainer/engine instance, matching
  // what actually happens when the app process is killed and relaunched.
  test(
    'MVP journey: real engine, real SmolLM2 — history persists across a '
    'controller/provider-container recreation over the same on-disk db '
    '(simulates an app restart), and export reflects it correctly',
    () async {
      final tmpDir = Directory.systemTemp.createTempSync(
        'dhruva_restart_test_',
      );
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });
      final dbFile = File('${tmpDir.path}/dhruva.sqlite');

      // ---- "session 1": send a real message, then tear everything down ----
      var db = AppDatabase(NativeDatabase(dbFile));
      var engine = LlamaEngineService(libraryPath: paths!.libraryPath);

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

      var container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          engineServiceProvider.overrideWithValue(engine),
        ],
      );

      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      var notifier = container.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('What color is the sky? One word answer.');

      final sessionOneState = container
          .read(chatControllerProvider(args))
          .value!;
      final conversationId = sessionOneState.conversationId!;
      final firstAssistantReply = sessionOneState.messages.last.content;
      expect(firstAssistantReply.trim(), isNotEmpty);

      // Genuine teardown — dispose the container (cancels streams/timers),
      // close the drift connection, and dispose the engine's worker isolate.
      // Nothing survives except what's on disk.
      container.dispose();
      await engine.dispose();
      await db.close();

      // ---- "session 2": brand-new db connection, container, engine ----
      db = AppDatabase(NativeDatabase(dbFile));
      engine = LlamaEngineService(libraryPath: paths.libraryPath);
      addTearDown(() async {
        await engine.dispose();
        await db.close();
      });

      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          engineServiceProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(container.dispose);

      final restartedArgs = ChatRouteArgs(conversationId: conversationId);
      await container.read(chatControllerProvider(restartedArgs).future);
      final restarted = container
          .read(chatControllerProvider(restartedArgs))
          .value!;

      // The conversation, its model link, and both messages survived.
      expect(restarted.conversationId, conversationId);
      expect(restarted.modelId, modelId);
      expect(restarted.messages, hasLength(2));
      expect(restarted.messages[0].role, MessageRole.user);
      expect(restarted.messages[1].role, MessageRole.assistant);
      expect(restarted.messages[1].content, firstAssistantReply);
      expect(restarted.messages[1].status, MessageStatus.complete);

      // A second real turn works fine post-restart, proving the reopened
      // controller isn't just replaying stale state — it can keep chatting.
      notifier = container.read(chatControllerProvider(restartedArgs).notifier);
      await notifier.sendMessage('And the grass — what color? One word.');
      final afterSecondTurn = container
          .read(chatControllerProvider(restartedArgs))
          .value!;
      expect(afterSecondTurn.messages, hasLength(4));
      expect(afterSecondTurn.messages.last.content.trim(), isNotEmpty);

      // Export reflects the full, persisted, multi-session history.
      final repo = ChatRepository(db: db);
      final markdown = await repo.exportConversationMarkdown(conversationId);
      expect(markdown, contains('What color is the sky? One word answer.'));
      expect(markdown, contains(firstAssistantReply));
      expect(markdown, contains('And the grass — what color? One word.'));
      expect(markdown, contains(afterSecondTurn.messages.last.content));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
