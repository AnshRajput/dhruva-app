import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/state/engine_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertModel({String repoId = 'bartowski/Some-Model-GGUF'}) {
    return db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: repoId,
            fileName: 'model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-test-model.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
  }

  ProviderContainer buildContainer(FakeEngineService engine) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'sendMessage streams tokens, batches flushes, finalizes with stats',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: const ['Hel', 'lo', ' wor', 'ld', '!', '!'],
        tokenDelay: const Duration(milliseconds: 40),
      );
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);

      final observedLengths = <int>[];
      container.listen(chatControllerProvider(args), (previous, next) {
        final content = next.value?.messages.lastOrNull?.content.length ?? -1;
        if (observedLengths.isEmpty || observedLengths.last != content) {
          observedLengths.add(content);
        }
      });

      final notifier = container.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('hi');

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.conversationId, isNotNull);
      expect(state.messages, hasLength(2));
      final assistant = state.messages.last;
      expect(assistant.content, 'Hello world!!');
      expect(assistant.status, MessageStatus.complete);
      expect(assistant.tokCount, 6);
      expect(state.isGenerating, isFalse);
      expect(state.streamingMessageId, isNull);
      // Content grew in more than one visible step — proves batching flushed
      // more than once during a stream that outlasts one 100ms tick, not a
      // single empty->final jump.
      expect(observedLengths.length, greaterThan(2));

      expect(container.read(loadedModelIdProvider), modelId);
    },
  );

  test(
    'cancel mid-stream finalizes as cancelled with partial content',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: List.generate(20, (i) => 'tok$i '),
        tokenDelay: const Duration(milliseconds: 30),
      );
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      final notifier = container.read(chatControllerProvider(args).notifier);

      final sendFuture = notifier.sendMessage('go');
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await notifier.cancel();
      await sendFuture;

      final state = container.read(chatControllerProvider(args)).value!;
      final assistant = state.messages.last;
      expect(assistant.status, MessageStatus.cancelled);
      expect(assistant.content, isNotEmpty);
      expect(assistant.content.trim().split(' ').length, lessThan(20));
      expect(state.isGenerating, isFalse);
    },
  );

  group('error taxonomy', () {
    final cases = <String, EngineFailure>{
      'EngineOutOfMemoryFailure': const EngineOutOfMemoryFailure(
        'needs more RAM',
      ),
      'EngineLoadFailure': const EngineLoadFailure('bad file'),
      'EngineDecodeFailure': const EngineDecodeFailure('decode broke'),
      'EngineUnknownFailure': const EngineUnknownFailure('mystery'),
    };

    for (final entry in cases.entries) {
      test(
        'a generate() failure (${entry.key}) finalizes the message as error',
        () async {
          final modelId = await insertModel();
          final engine = FakeEngineService(generateFailure: entry.value);
          final container = buildContainer(engine);
          final args = ChatRouteArgs(initialModelId: modelId);
          await container.read(chatControllerProvider(args).future);
          final notifier = container.read(
            chatControllerProvider(args).notifier,
          );

          await notifier.sendMessage('hi');

          final state = container.read(chatControllerProvider(args)).value!;
          final assistant = state.messages.last;
          expect(assistant.status, MessageStatus.error);
          expect(assistant.errorKind, entry.key);
          expect(notifier.errorDetailsFor(assistant.id), entry.value.message);
          expect(state.isGenerating, isFalse);
        },
      );
    }
  });

  test(
    'a model load failure surfaces as modelLoadError, no assistant row created',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        loadFailure: const EngineLoadFailure('corrupt gguf'),
      );
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      final notifier = container.read(chatControllerProvider(args).notifier);

      await notifier.sendMessage('hi');

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.modelLoadError, isA<EngineLoadFailure>());
      expect(state.messages, hasLength(1)); // only the user message
    },
  );

  test(
    'no model selected: sendMessage sets modelLoadError, still records the user turn',
    () async {
      final container = buildContainer(FakeEngineService());
      const args = ChatRouteArgs();
      await container.read(chatControllerProvider(args).future);
      final notifier = container.read(chatControllerProvider(args).notifier);

      await notifier.sendMessage('hi');

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.messages, hasLength(1));
      expect(state.modelLoadError, isNotNull);
    },
  );

  group('<think> extraction', () {
    test(
      'a closed think block splits into reasoningContent vs content, tag split across tokens',
      () async {
        final modelId = await insertModel();
        final engine = FakeEngineService(
          scriptedTokens: const [
            '<thi',
            'nk>rea',
            'soning here</th',
            'ink>the answer',
          ],
          tokenDelay: const Duration(milliseconds: 10),
        );
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);
        await container.read(chatControllerProvider(args).future);
        final notifier = container.read(chatControllerProvider(args).notifier);

        await notifier.sendMessage('explain');

        final state = container.read(chatControllerProvider(args)).value!;
        final assistant = state.messages.last;
        expect(assistant.reasoningContent, 'reasoning here');
        expect(assistant.content, 'the answer');
        expect(state.reasoningDurationMs[assistant.id], isNotNull);
      },
    );

    test(
      'an unclosed think tag: entire message is treated as reasoning',
      () async {
        final modelId = await insertModel();
        final engine = FakeEngineService(
          scriptedTokens: const ['<think>', 'never ', 'closes ', 'at all'],
          tokenDelay: const Duration(milliseconds: 10),
        );
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);
        await container.read(chatControllerProvider(args).future);
        final notifier = container.read(chatControllerProvider(args).notifier);

        await notifier.sendMessage('explain');

        final state = container.read(chatControllerProvider(args)).value!;
        final assistant = state.messages.last;
        expect(assistant.reasoningContent, 'never closes at all');
        expect(assistant.content, isEmpty);
        // Never closed -> no wall-clock duration was ever recorded for it.
        expect(state.reasoningDurationMs.containsKey(assistant.id), isFalse);
      },
    );

    test(
      'no think tag at all: content is the full text, reasoningContent is null',
      () async {
        final modelId = await insertModel();
        final engine = FakeEngineService(
          scriptedTokens: const ['plain ', 'answer'],
        );
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);
        await container.read(chatControllerProvider(args).future);
        final notifier = container.read(chatControllerProvider(args).notifier);

        await notifier.sendMessage('hi');

        final assistant = container
            .read(chatControllerProvider(args))
            .value!
            .messages
            .last;
        expect(assistant.content, 'plain answer');
        expect(assistant.reasoningContent, isNull);
      },
    );
  });

  test(
    'regenerate supersedes the old assistant reply with a new lineage row',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(scriptedTokens: const ['first']);
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      final notifier = container.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('hi');
      final firstAssistantId = container
          .read(chatControllerProvider(args))
          .value!
          .messages
          .last
          .id;

      await notifier.regenerate(firstAssistantId);

      final state = container.read(chatControllerProvider(args)).value!;
      final visibleAssistants = state.visibleMessages.where(
        (m) => m.role == MessageRole.assistant,
      );
      expect(visibleAssistants, hasLength(1));
      final newAssistant = visibleAssistants.single;
      expect(newAssistant.id, isNot(firstAssistantId));
      expect(newAssistant.parentMessageId, firstAssistantId);
    },
  );

  test(
    'editMessage supersedes the user turn and re-runs the assistant reply',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(scriptedTokens: const ['answer']);
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      final notifier = container.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('what is 2+2');
      final userMsgId = container
          .read(chatControllerProvider(args))
          .value!
          .messages
          .first
          .id;

      await notifier.editMessage(userMsgId, 'what is 3+3');

      final state = container.read(chatControllerProvider(args)).value!;
      final visible = state.visibleMessages;
      expect(
        visible.where((m) => m.role == MessageRole.user).single.content,
        'what is 3+3',
      );
      expect(
        visible.where((m) => m.role == MessageRole.assistant),
        hasLength(1),
      );
    },
  );

  test(
    'switchModel persists the new modelId and loads it, touching lastUsedAt',
    () async {
      final modelA = await insertModel(repoId: 'org/model-a-GGUF');
      final modelB = await insertModel(repoId: 'org/model-b-GGUF');
      final engine = FakeEngineService(scriptedTokens: const ['hi']);
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelA);
      await container.read(chatControllerProvider(args).future);
      final notifier = container.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('start');

      final modelBInfo = await container
          .read(storageManagerProvider)
          .getInstalledModel(modelB);
      await notifier.switchModel(modelBInfo!);

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.modelId, modelB);
      expect(container.read(loadedModelIdProvider), modelB);
      final refreshed = await container
          .read(storageManagerProvider)
          .getInstalledModel(modelB);
      expect(refreshed!.lastUsedAt, isNotNull);
    },
  );
}
