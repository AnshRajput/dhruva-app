import 'dart:convert';
import 'dart:typed_data';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/state/engine_session.dart';
import 'package:drift/drift.dart' show Value;
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

  // Loop 7: a vision-capable installed row — mmprojPath set, same shape
  // Loop-7 T2's pairing flow leaves on `installed_models` once a projector
  // has landed (`InstalledModelInfo.needsProjector` == false).
  Future<int> insertVisionModel({
    String repoId = 'ggml-org/Some-Vision-Model-GGUF',
    String mmprojPath = '/tmp/dhruva-test-mmproj.gguf',
  }) {
    return db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: repoId,
            fileName: 'vision-model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-test-vision-model.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
            mmprojPath: Value(mmprojPath),
            isVision: const Value(true),
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

  group('Loop 5: character-bound conversations', () {
    Future<int> insertCharacter({
      String name = 'Code Reviewer',
      required String personaSystemPrompt,
      String? greeting,
      int? defaultModelId,
      SamplingParams? samplingParams,
    }) {
      final now = DateTime.now();
      return db
          .into(db.characters)
          .insert(
            CharactersCompanion.insert(
              name: name,
              personaSystemPrompt: personaSystemPrompt,
              greeting: Value(greeting),
              defaultModelId: Value(defaultModelId),
              samplingParamsJson: Value(
                samplingParams == null
                    ? null
                    : jsonEncode(samplingParams.toJson()),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    test('a character-bound conversation sends the persona as the system '
        'prompt to the engine (gate G1)', () async {
      const persona =
          'You are a strict senior code reviewer. Be terse and critical.';
      final modelId = await insertModel();
      final characterId = await insertCharacter(
        personaSystemPrompt: persona,
        greeting: 'Show me the code.',
      );
      final engine = FakeEngineService();
      final container = buildContainer(engine);
      final args = ChatRouteArgs(
        initialModelId: modelId,
        characterId: characterId,
      );

      // Building the controller itself creates the conversation row
      // eagerly (chat-spec §1's "never a row for an empty draft" rule is
      // the ordinary-draft case; a character's greeting is content the
      // user should see before typing anything, so this one seeds
      // immediately — see ChatController._buildFromCharacter's doc).
      final state = await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      expect(state.conversationId, isNotNull);
      expect(state.characterId, characterId);
      expect(state.systemPrompt, persona);
      expect(state.messages, hasLength(1));
      expect(state.messages.single.role, MessageRole.assistant);
      expect(state.messages.single.content, 'Show me the code.');

      final notifier = container.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('Review this: print("hi")');

      // The actual gate: what reached the "engine" (FakeEngineService's
      // test hook records exactly what generate() was called with) must
      // include the persona as a system turn — not just that the
      // controller's own state object carries it.
      final sentMessages = engine.lastMessages;
      expect(sentMessages, isNotNull);
      expect(
        sentMessages!.first,
        isA<ChatTurn>()
            .having((t) => t.role, 'role', EngineRole.system)
            .having((t) => t.content, 'content', persona),
      );
      // The greeting and the new user turn both rode along too.
      expect(
        sentMessages.any(
          (t) =>
              t.role == EngineRole.assistant &&
              t.content == 'Show me the code.',
        ),
        isTrue,
      );
      expect(
        sentMessages.any(
          (t) =>
              t.role == EngineRole.user &&
              t.content == 'Review this: print("hi")',
        ),
        isTrue,
      );
    });

    test("a character's default model + sampling override apply when the "
        'conversation is created', () async {
      final modelId = await insertModel(repoId: 'bartowski/Character-Model');
      final characterId = await insertCharacter(
        personaSystemPrompt: 'Be terse.',
        defaultModelId: modelId,
        samplingParams: const SamplingParams(temperature: 0.1),
      );
      final container = buildContainer(FakeEngineService());
      final args = ChatRouteArgs(characterId: characterId);

      final state = await container.read(chatControllerProvider(args).future);
      expect(state.modelId, modelId);
      expect(state.samplingParams.temperature, 0.1);
    });

    test('a deleted character degrades to an ordinary model-only draft '
        'instead of erroring', () async {
      final modelId = await insertModel();
      final container = buildContainer(FakeEngineService());
      // 999 was never inserted — chatContextFor returns null.
      final args = ChatRouteArgs(initialModelId: modelId, characterId: 999);

      final state = await container.read(chatControllerProvider(args).future);
      expect(state.characterId, isNull);
      expect(state.conversationId, isNull);
      expect(state.modelId, modelId);
    });

    test(
      'regenerating a character-bound turn keeps sending the persona',
      () async {
        const persona = 'You are Aria, a sarcastic night-shift barista.';
        final modelId = await insertModel();
        final characterId = await insertCharacter(personaSystemPrompt: persona);
        final engine = FakeEngineService();
        final container = buildContainer(engine);
        final args = ChatRouteArgs(
          initialModelId: modelId,
          characterId: characterId,
        );
        await container.read(chatControllerProvider(args).future);
        container.listen(chatControllerProvider(args), (_, _) {});
        final notifier = container.read(chatControllerProvider(args).notifier);

        await notifier.sendMessage('hi');
        final assistantId = container
            .read(chatControllerProvider(args))
            .value!
            .messages
            .last
            .id;
        await notifier.regenerate(assistantId);

        expect(
          engine.lastMessages!.first,
          isA<ChatTurn>()
              .having((t) => t.role, 'role', EngineRole.system)
              .having((t) => t.content, 'content', persona),
        );
      },
    );

    test('attack list #3: a character with an empty/whitespace-only persona '
        'never sends an empty system turn to the engine (the form/import '
        'validation that should normally prevent this is a UI/import-layer '
        'concern, not something ChatController can rely on — see '
        'character_repository_test.dart\'s INFO note that createCharacter '
        'itself does not reject a blank persona)', () async {
      final modelId = await insertModel();
      final characterId = await insertCharacter(
        personaSystemPrompt: '   ',
        greeting: 'Hi!',
      );
      final engine = FakeEngineService();
      final container = buildContainer(engine);
      final args = ChatRouteArgs(
        initialModelId: modelId,
        characterId: characterId,
      );
      final state = await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      expect(state.systemPrompt.trim(), isEmpty);

      final notifier = container.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('hi');

      final sentMessages = engine.lastMessages!;
      expect(
        sentMessages.any((t) => t.role == EngineRole.system),
        isFalse,
        reason:
            '_historyTurns only adds a system ChatTurn when '
            'systemPrompt.trim().isNotEmpty — a blank persona must not '
            'become an empty system turn',
      );
    });

    test('attack list #3: editing a character AFTER a conversation with it has '
        'started does NOT retroactively change that conversation — the '
        'persona is snapshotted onto Conversations.systemPrompt at creation '
        'time, not re-read from the character on every turn. Reopening the '
        'SAME conversation (fresh ChatController, simulating an app restart) '
        'still sends the OLD persona.', () async {
      final modelId = await insertModel();
      final characterId = await insertCharacter(
        personaSystemPrompt: 'Persona v1: be terse.',
      );
      final engine = FakeEngineService();
      final container = buildContainer(engine);
      final args = ChatRouteArgs(
        initialModelId: modelId,
        characterId: characterId,
      );
      final initial = await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final conversationId = initial.conversationId!;

      // Edit the character's persona directly (same thing
      // CharacterRepository.updateCharacter does under the hood).
      await (db.update(
        db.characters,
      )..where((t) => t.id.equals(characterId))).write(
        const CharactersCompanion(
          personaSystemPrompt: Value('Persona v2: be verbose and flowery.'),
        ),
      );

      // Reopen the SAME conversation via a brand-new ChatController
      // (args keyed by conversationId now, like a real re-navigation).
      final reopenArgs = ChatRouteArgs(conversationId: conversationId);
      final reopened = await container.read(
        chatControllerProvider(reopenArgs).future,
      );
      container.listen(chatControllerProvider(reopenArgs), (_, _) {});
      expect(reopened.systemPrompt, 'Persona v1: be terse.');

      final notifier = container.read(
        chatControllerProvider(reopenArgs).notifier,
      );
      await notifier.sendMessage('hi again');

      expect(
        engine.lastMessages!.first,
        isA<ChatTurn>()
            .having((t) => t.role, 'role', EngineRole.system)
            .having((t) => t.content, 'content', 'Persona v1: be terse.'),
        reason:
            'a live/open conversation keeps its persona snapshot; only a '
            'NEW conversation started with the character would pick up '
            "the edited persona — this is sane (matches the model's own "
            'design/greeting/sampling that were also snapshotted at '
            'creation) but is worth pinning explicitly.',
      );
    });
  });

  group('Loop 7: vision', () {
    test(
      'load path carries the projector: mmprojPath reaches EngineLoadParams, '
      'isMultimodal state flips on once the engine confirms it (G3 wiring)',
      () async {
        final modelId = await insertVisionModel(
          mmprojPath: '/tmp/dhruva-test-mmproj.gguf',
        );
        final engine = FakeEngineService(multimodal: true);
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);
        await container.read(chatControllerProvider(args).future);
        container.listen(chatControllerProvider(args), (_, _) {});
        final notifier = container.read(chatControllerProvider(args).notifier);

        await notifier.ensureModelLoaded();

        expect(
          engine.lastLoadParams?.mmprojPath,
          '/tmp/dhruva-test-mmproj.gguf',
        );
        final state = container.read(chatControllerProvider(args)).value!;
        expect(state.isMultimodal, isTrue);
      },
    );

    test(
      'a text-only model never sets mmprojPath, isMultimodal stays false',
      () async {
        final modelId = await insertModel();
        final engine = FakeEngineService();
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);
        await container.read(chatControllerProvider(args).future);
        container.listen(chatControllerProvider(args), (_, _) {});
        final notifier = container.read(chatControllerProvider(args).notifier);

        await notifier.ensureModelLoaded();

        expect(engine.lastLoadParams?.mmprojPath, isNull);
        final state = container.read(chatControllerProvider(args)).value!;
        expect(state.isMultimodal, isFalse);
      },
    );

    test('D2: sendMessage with imageBytes builds a ChatTurn carrying the '
        "image, and the engine's grounded vision answer lands as the "
        'assistant reply', () async {
      final modelId = await insertVisionModel();
      final engine = FakeEngineService(
        multimodal: true,
        visionTokens: const ['I ', 'see ', 'red', '.'],
      );
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
      await notifier.sendMessage('What color is this?', imageBytes: imageBytes);

      expect(engine.lastImageCount, 1);
      final userTurn = engine.lastMessages!.firstWhere(
        (t) => t.role == EngineRole.user,
      );
      expect(userTurn.images, [imageBytes]);

      final state = container.read(chatControllerProvider(args)).value!;
      final assistant = state.messages.last;
      expect(assistant.content, 'I see red.');
      expect(state.attachedImages[state.messages.first.id], imageBytes);
    });

    test('sending with only an image (no text) is a valid turn', () async {
      final modelId = await insertVisionModel();
      final engine = FakeEngineService(multimodal: true);
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      await notifier.sendMessage('', imageBytes: Uint8List.fromList([9]));

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.messages, hasLength(2));
      expect(state.messages.first.content, isEmpty);
    });

    test('guard: an image attached against a non-multimodal (text-only) model '
        "never reaches the engine's generate() call — dropped there, even "
        'though the bubble still has it to render (composer.dart hiding the '
        'attach button for this case is the primary defense; this is the '
        'belt-and-suspenders backstop)', () async {
      final modelId = await insertModel(); // text-only, no mmprojPath
      final engine = FakeEngineService(); // multimodal: false (default)
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      await notifier.sendMessage(
        'describe this',
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(engine.lastImageCount, 0);
      final sentMessages = engine.lastMessages!;
      expect(sentMessages.every((t) => t.images.isEmpty), isTrue);
    });

    test(
      "regenerate keeps the original turn's image attached (attachedImages "
      'is keyed by message id, not overwritten by the new assistant turn)',
      () async {
        final modelId = await insertVisionModel();
        final engine = FakeEngineService(multimodal: true);
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);
        await container.read(chatControllerProvider(args).future);
        container.listen(chatControllerProvider(args), (_, _) {});
        final notifier = container.read(chatControllerProvider(args).notifier);

        final imageBytes = Uint8List.fromList([5, 5, 5]);
        await notifier.sendMessage('what is this', imageBytes: imageBytes);
        final assistantId = container
            .read(chatControllerProvider(args))
            .value!
            .messages
            .last
            .id;

        await notifier.regenerate(assistantId);

        expect(engine.lastImageCount, 1);
        final userTurn = engine.lastMessages!.firstWhere(
          (t) => t.role == EngineRole.user,
        );
        expect(userTurn.images, [imageBytes]);
      },
    );

    // QA attack 2: the "needs projector" half-state (Loop-7 T2 HANDOFF) —
    // `isVision: true, mmprojPath: null` on the installed row (model landed,
    // its mmproj download failed/hasn't happened yet). The row must still
    // load and chat normally as a text-only model: no crash trying to hand
    // the engine a null projector path, and the attach button stays gated
    // off (isMultimodal false). engine_vision_test.dart already proves this
    // one level down (bare EngineService, mmprojPath: null loads text-only);
    // this test closes the loop through the InstalledModelInfo row + the
    // controller's own load path.
    test(
      'a vision model row missing its projector (needsProjector half-state) '
      'loads and chats as text-only, no crash, attach stays gated off',
      () async {
        final modelId = await db
            .into(db.installedModels)
            .insert(
              InstalledModelsCompanion.insert(
                repoId: 'ggml-org/Needs-Projector-GGUF',
                fileName: 'needs-projector.gguf',
                sizeBytes: 100,
                localPath: '/tmp/dhruva-test-needs-projector.gguf',
                downloadedAt: DateTime.utc(2026, 7, 17),
                isVision: const Value(true),
                // mmprojPath left null (the default) — the half-state.
              ),
            );
        final engine = FakeEngineService(); // multimodal: false (default)
        final container = buildContainer(engine);
        final args = ChatRouteArgs(initialModelId: modelId);
        await container.read(chatControllerProvider(args).future);
        container.listen(chatControllerProvider(args), (_, _) {});
        final notifier = container.read(chatControllerProvider(args).notifier);

        await notifier.ensureModelLoaded();

        // Never even attempts to pass a projector path to the engine.
        expect(engine.lastLoadParams?.mmprojPath, isNull);
        var state = container.read(chatControllerProvider(args)).value!;
        expect(state.modelLoadError, isNull, reason: 'load should not fail');
        expect(state.isMultimodal, isFalse);

        // And it's still a perfectly usable text-only chat.
        await notifier.sendMessage('hello');
        state = container.read(chatControllerProvider(args)).value!;
        expect(state.messages.last.status.toString(), contains('complete'));
      },
    );

    // QA attack 5: switching the conversation's model from vision to
    // text-only mid-conversation. The attach gate must follow the NEW
    // model (hide), but images already attached to earlier turns are keyed
    // by message id in session state, independent of which model is
    // currently loaded — chat_thread_screen.dart renders them off that map
    // regardless, so they must survive the switch.
    test('switching from a vision model to a text-only model mid-conversation: '
        'isMultimodal flips false (attach hides) but earlier attachedImages '
        'entries are untouched (bubbles still render them)', () async {
      final visionModelId = await insertVisionModel();
      final engine = FakeEngineService(multimodal: true);
      final container = buildContainer(engine);
      final args = ChatRouteArgs(initialModelId: visionModelId);
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      final imageBytes = Uint8List.fromList([7, 7, 7]);
      await notifier.sendMessage('what is this', imageBytes: imageBytes);
      var state = container.read(chatControllerProvider(args)).value!;
      expect(state.isMultimodal, isTrue);
      final userMsgId = state.messages.first.id;
      expect(state.attachedImages[userMsgId], imageBytes);

      // FakeEngineService.multimodal is fixed per-instance (it models
      // "whichever model is currently loaded"); a real engine's
      // isMultimodal would flip per `load()` call based on that model's
      // own mmprojPath. Model the same effect here by loading a
      // text-only model next — ensureModelLoaded reads engine.isMultimodal
      // fresh after that load either way.
      final textEngine = FakeEngineService();
      final textModelId = await insertModel(
        repoId: 'bartowski/Some-Text-Model-GGUF',
      );
      final textModel = await container
          .read(storageManagerProvider)
          .getInstalledModel(textModelId);

      final container2 = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          engineServiceProvider.overrideWithValue(textEngine),
        ],
      );
      addTearDown(container2.dispose);
      final args2 = ChatRouteArgs(conversationId: state.conversationId);
      await container2.read(chatControllerProvider(args2).future);
      container2.listen(chatControllerProvider(args2), (_, _) {});
      final notifier2 = container2.read(chatControllerProvider(args2).notifier);

      await notifier2.switchModel(textModel!);
      state = container2.read(chatControllerProvider(args2)).value!;
      expect(state.isMultimodal, isFalse, reason: 'attach button hides');
      // The earlier turn's image is still there for the bubble to render
      // — reloaded fresh from the repo (this is a NEW controller/
      // container reading the same conversation, the closest in-memory
      // proxy for "re-opened the thread after switching models" this
      // session-only map's own design allows) plus this session's own
      // send above; either way the message list/thumbnail keying is
      // untouched by switchModel, which only ever writes isMultimodal/
      // model/modelId.
      expect(
        state.messages.any((m) => m.id == userMsgId),
        isTrue,
        reason: 'the earlier image message itself is not dropped',
      );
    });
  });

  group('Loop 7: vision + character (QA attack 5)', () {
    test('a character-bound conversation with an attached image: persona '
        'system prompt AND the image both reach the engine on the same turn '
        "(persona + image aren't mutually exclusive code paths)", () async {
      const persona = 'You are a cheerful art critic.';
      final modelId = await insertVisionModel();
      final characterId = await db
          .into(db.characters)
          .insert(
            CharactersCompanion.insert(
              name: 'Art Critic',
              personaSystemPrompt: persona,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      final engine = FakeEngineService(multimodal: true);
      final container = buildContainer(engine);
      final args = ChatRouteArgs(
        initialModelId: modelId,
        characterId: characterId,
      );
      await container.read(chatControllerProvider(args).future);
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      final imageBytes = Uint8List.fromList([3, 1, 4]);
      await notifier.sendMessage(
        'What do you think of this piece?',
        imageBytes: imageBytes,
      );

      expect(engine.lastImageCount, 1);
      final sent = engine.lastMessages!;
      expect(
        sent.first,
        isA<ChatTurn>()
            .having((t) => t.role, 'role', EngineRole.system)
            .having((t) => t.content, 'content', persona),
      );
      final userTurn = sent.firstWhere((t) => t.role == EngineRole.user);
      expect(userTurn.images, [imageBytes]);

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.characterId, characterId);
      expect(state.attachedImages[state.messages.first.id], imageBytes);
    });
  });
}
