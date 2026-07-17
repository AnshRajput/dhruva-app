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

  // B1: chatControllerProvider is autoDispose, kept alive in the real app
  // by the ChatThreadScreen's own `ref.watch` for as long as it's mounted.
  // Every test below stands that in for with a `container.listen(...)`
  // right after its first `.future` read — without it, the provider can
  // be reclaimed between there and a later `container.read(...).value!`
  // in the same test, since nothing else in a widget-less container test
  // holds a subscription open.
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
      container.listen(chatControllerProvider(args), (_, _) {});

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
      container.listen(chatControllerProvider(args), (_, _) {});
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
          container.listen(chatControllerProvider(args), (_, _) {});
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
      container.listen(chatControllerProvider(args), (_, _) {});
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
      container.listen(chatControllerProvider(args), (_, _) {});
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
        container.listen(chatControllerProvider(args), (_, _) {});
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
        container.listen(chatControllerProvider(args), (_, _) {});
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
        container.listen(chatControllerProvider(args), (_, _) {});
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

    test('N1 (staff review): nested <think> markers streamed one character at '
        'a time never let the persisted row diverge from the final in-memory '
        'content — even where a re-derived split shrinks relative to what '
        'was already pushed, `_flush` rewrites the row instead of appending '
        'a delta against a stale prefix. Same QA nested-think sequence as '
        'think_tag_parser_test.dart\'s repro, run through the real '
        'controller/repository instead of the pure parser function.', () async {
      final modelId = await insertModel();
      const raw = '<think>outer <think>inner</think> tail</think>after';
      // One character per token, spread comfortably past the 100ms
      // flush tick relative to the 7-char opening tag — this reliably
      // lands a periodic flush mid-formation of "<think>" (still short
      // enough to hit `safeThinkPrefix`'s own <=holdback bypass and read
      // as plain content), then a later flush resolving it into the
      // real opener shrinks `content` — exactly N1's guard case.
      final engine = FakeEngineService(
        scriptedTokens: raw.split(''),
        tokenDelay: const Duration(milliseconds: 20),
      );
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      await notifier.sendMessage('explain');

      final state = container.read(chatControllerProvider(args)).value!;
      final assistant = state.messages.last;
      // Same expectations as think_tag_parser_test.dart's fixed repro:
      // only the first opener/closer pair becomes reasoning, and the
      // leftover literal tag markers are stripped rather than leaked.
      expect(assistant.reasoningContent, 'outer <think>inner');
      expect(assistant.content, ' tailafter');

      // N1's actual point: the persisted row matches that exactly —
      // no divergence from an append-only delta computed against a
      // `_pushedContent` a mid-stream shrink left stale.
      final persisted =
          (await container
                  .read(chatRepositoryProvider)
                  .getMessages(state.conversationId!))
              .last;
      expect(persisted.content, assistant.content);
      expect(persisted.reasoningContent, assistant.reasoningContent);
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  test(
    'regenerate supersedes the old assistant reply with a new lineage row',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(scriptedTokens: const ['first']);
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
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
      container.listen(chatControllerProvider(args), (_, _) {});
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
      container.listen(chatControllerProvider(args), (_, _) {});
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

  // ---- QA (Loop-4 attack list #2): streaming robustness -------------------

  test(
    'regenerate is a no-op while a generation is already in flight',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: List.generate(10, (i) => 'tok$i '),
        tokenDelay: const Duration(milliseconds: 30),
      );
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      final sendFuture = notifier.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 45));
      final duringStream = container.read(chatControllerProvider(args)).value!;
      expect(duringStream.isGenerating, isTrue);
      final assistantId = duringStream.messages.last.id;
      final countDuringStream = duringStream.messages.length;

      // Blocked, not queued: ChatController.regenerate checks isGenerating
      // and returns early — it does not interrupt or enqueue behind the
      // active stream.
      await notifier.regenerate(assistantId);
      final afterAttempt = container.read(chatControllerProvider(args)).value!;
      expect(afterAttempt.messages.length, countDuringStream);

      await sendFuture;
      final finalState = container.read(chatControllerProvider(args)).value!;
      expect(
        finalState.visibleMessages.where(
          (m) => m.role == MessageRole.assistant,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'editMessage is a no-op while a generation is already in flight',
    () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: List.generate(10, (i) => 'tok$i '),
        tokenDelay: const Duration(milliseconds: 30),
      );
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      final sendFuture = notifier.sendMessage('what is 2+2');
      await Future<void>.delayed(const Duration(milliseconds: 45));
      final duringStream = container.read(chatControllerProvider(args)).value!;
      expect(duringStream.isGenerating, isTrue);
      final userMsgId = duringStream.messages.first.id;
      final countDuringStream = duringStream.messages.length;

      await notifier.editMessage(userMsgId, 'what is 3+3');
      final afterAttempt = container.read(chatControllerProvider(args)).value!;
      expect(afterAttempt.messages.length, countDuringStream);
      expect(afterAttempt.messages.first.content, 'what is 2+2');

      await sendFuture;
    },
  );

  test('FIXED (QA BUG-2): switchModel is a no-op while a generation is already '
      'in flight, same as regenerate/editMessage — the chip/state stays on '
      'the OLD model and the engine singleton is untouched, instead of the '
      'chip flipping to a model the engine never actually loaded', () async {
    final modelA = await insertModel(repoId: 'org/model-a-GGUF');
    final modelB = await insertModel(repoId: 'org/model-b-GGUF');
    final engine = FakeEngineService(
      scriptedTokens: List.generate(10, (i) => 'tok$i '),
      tokenDelay: const Duration(milliseconds: 30),
    );
    final container = buildContainer(engine);
    final args = ChatRouteArgs(initialModelId: modelA);
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    final notifier = container.read(chatControllerProvider(args).notifier);

    final sendFuture = notifier.sendMessage('hi');
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(
      container.read(chatControllerProvider(args)).value!.isGenerating,
      isTrue,
    );

    final modelBInfo = await container
        .read(storageManagerProvider)
        .getInstalledModel(modelB);
    await notifier.switchModel(modelBInfo!);

    // Blocked, not applied: switchModel's isGenerating guard returns
    // early before touching state or the repository, so both the
    // conversation's persisted modelId and the UI-visible chip stay on
    // model A throughout the in-flight stream.
    final mid = container.read(chatControllerProvider(args)).value!;
    expect(mid.modelId, modelA);
    expect(container.read(loadedModelIdProvider), modelA);

    await sendFuture;
    final finalState = container.read(chatControllerProvider(args)).value!;
    expect(finalState.messages.last.status, MessageStatus.complete);
    // Persisted modelId in the repository also never moved.
    final persisted = await container
        .read(chatRepositoryProvider)
        .getConversation(finalState.conversationId!);
    expect(persisted!.modelId, modelA);
  });

  test('unloading the engine mid-stream finalizes the message as cancelled, '
      'conversation intact — NOT a typed error; unload() takes the same '
      'graceful-cancellation path as user cancel() in both FakeEngineService '
      'and LlamaEngineService (pinning actual behavior)', () async {
    final modelId = await insertModel();
    final engine = FakeEngineService(
      scriptedTokens: List.generate(20, (i) => 'tok$i '),
      tokenDelay: const Duration(milliseconds: 30),
    );
    final container = buildContainer(engine);
    final args = ChatRouteArgs(initialModelId: modelId);
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    final notifier = container.read(chatControllerProvider(args).notifier);

    final sendFuture = notifier.sendMessage('go');
    await Future<void>.delayed(const Duration(milliseconds: 90));
    // Simulate the model being unloaded out from under the stream (e.g. a
    // memory-pressure eviction elsewhere in the app) — bypasses the
    // controller's own cancel() entirely.
    await engine.unload();
    await sendFuture;

    final state = container.read(chatControllerProvider(args)).value!;
    final assistant = state.messages.last;
    expect(assistant.status, MessageStatus.cancelled);
    expect(state.isGenerating, isFalse);
    expect(state.modelLoadError, isNull);
    expect(state.conversationId, isNotNull);
  });

  test('BUG repro: a 0-token assistant response finalizes as an empty, '
      'complete-status message that stays in visibleMessages once '
      'streamingMessageId clears — see chat_thread_screen_test.dart for the '
      'resulting "ghost bubble" render', () async {
    final modelId = await insertModel();
    final engine = FakeEngineService(scriptedTokens: const []);
    final container = buildContainer(engine);
    final args = ChatRouteArgs(initialModelId: modelId);
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    final notifier = container.read(chatControllerProvider(args).notifier);

    await notifier.sendMessage('hi');

    final state = container.read(chatControllerProvider(args)).value!;
    final assistant = state.messages.last;
    expect(assistant.content, isEmpty);
    expect(assistant.reasoningContent, anyOf(isNull, isEmpty));
    expect(assistant.status, MessageStatus.complete);
    expect(assistant.tokCount, 0);
    expect(state.visibleMessages.map((m) => m.id), contains(assistant.id));
    expect(state.streamingMessageId, isNull);
  });

  test('a think-only response (closes with no trailing content) leaves content '
      'empty and reasoningContent populated', () async {
    final modelId = await insertModel();
    final engine = FakeEngineService(
      scriptedTokens: const ['<think>', 'just reasoning', '</think>'],
      tokenDelay: const Duration(milliseconds: 10),
    );
    final container = buildContainer(engine);
    final args = ChatRouteArgs(initialModelId: modelId);
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    final notifier = container.read(chatControllerProvider(args).notifier);

    await notifier.sendMessage('explain');

    final state = container.read(chatControllerProvider(args)).value!;
    final assistant = state.messages.last;
    expect(assistant.reasoningContent, 'just reasoning');
    expect(assistant.content, isEmpty);
    expect(state.reasoningDurationMs[assistant.id], isNotNull);
  });

  // ---- Staff review B1: autoDispose + keepAlive lifecycle -----------------

  group('B1: autoDispose + keepAlive lifecycle', () {
    test('idle (not generating): once its only listener is dropped, the '
        'provider is disposed and rebuilt fresh on the next read', () async {
      final modelId = await insertModel();
      final engine = FakeEngineService();
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);

      final sub = container.listen(chatControllerProvider(args), (_, _) {});
      await container.read(chatControllerProvider(args).future);
      expect(container.exists(chatControllerProvider(args)), isTrue);

      // Simulates navigating away: the widget that was watching this
      // thread stops listening, and nothing is generating.
      sub.close();
      await container.pump();

      expect(container.exists(chatControllerProvider(args)), isFalse);
    });

    test(
      'while generating: dropping the listener does NOT dispose the '
      'provider (the self-held keepAlive covers it); completion releases '
      'that keepAlive and the now-idle provider becomes reclaimable again',
      () async {
        final modelId = await insertModel();
        final engine = FakeEngineService(
          scriptedTokens: List.generate(10, (i) => 'tok$i '),
          tokenDelay: const Duration(milliseconds: 30),
        );
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);

        final sub = container.listen(chatControllerProvider(args), (_, _) {});
        await container.read(chatControllerProvider(args).future);
        final notifier = container.read(chatControllerProvider(args).notifier);

        final sendFuture = notifier.sendMessage('hi');
        await Future<void>.delayed(const Duration(milliseconds: 45));
        expect(
          container.read(chatControllerProvider(args)).value!.isGenerating,
          isTrue,
        );

        // Drop the only external listener mid-stream (simulates
        // navigating away while a reply is still streaming in).
        sub.close();
        await container.pump();
        expect(
          container.exists(chatControllerProvider(args)),
          isTrue,
          reason:
              'the in-flight generation holds its own keepAlive — '
              'losing the last widget listener must not kill the stream',
        );

        await sendFuture;
        expect(
          container.read(chatControllerProvider(args)).value!.isGenerating,
          isFalse,
        );

        // Generation is over, its keepAlive released, and (from the
        // `sub.close()` above) there is still no listener — now the
        // provider is reclaimable like any other idle autoDispose provider.
        await container.pump();
        expect(container.exists(chatControllerProvider(args)), isFalse);
      },
    );
  });
}
