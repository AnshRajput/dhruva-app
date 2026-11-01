// D1 (Continue a stopped / cut-short reply) and D3 (warm-up phase, first-token
// timeout) in ChatController.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_health_fakes.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertModel() => db
      .into(db.installedModels)
      .insert(
        InstalledModelsCompanion.insert(
          repoId: 'r/m',
          fileName: 'model.gguf',
          sizeBytes: 100,
          localPath: '/tmp/m.gguf',
          downloadedAt: DateTime.utc(2026, 7, 17),
        ),
      );

  Future<(ProviderContainer, ChatRouteArgs, FakeEngineService)> setup({
    List<String> tokens = const ['a ', 'b ', 'c ', 'd ', 'e ', 'f '],
    Duration tokenDelay = const Duration(milliseconds: 10),
    Duration? firstTokenTimeout,
  }) async {
    final engine = FakeEngineService(
      scriptedTokens: tokens,
      tokenDelay: tokenDelay,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        if (firstTokenTimeout != null)
          firstTokenTimeoutProvider.overrideWithValue(firstTokenTimeout),
        ...deviceHealthTestOverrides(),
      ],
    );
    addTearDown(container.dispose);
    final args = ChatRouteArgs(initialModelId: await insertModel());
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    return (container, args, engine);
  }

  group('D1 continue', () {
    test('a reply cut by the answer-length limit is marked truncated and '
        'Continue appends to the same message', () async {
      final (c, args, engine) = await setup();
      final n = c.read(chatControllerProvider(args).notifier);
      await n.setSamplingParams(const SamplingParams(maxTokens: 2));
      await n.sendMessage('hi');

      var s = c.read(chatControllerProvider(args)).value!;
      final reply = s.messages.last;
      expect(reply.status, MessageStatus.truncated);
      expect(reply.content, 'a b ');
      // Persisted too, so the marker survives a restart (finalize is async).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final rows = await c
          .read(chatRepositoryProvider)
          .getMessages(s.conversationId!);
      expect(rows.last.status, MessageStatus.truncated);

      // Room to finish this time.
      await n.setSamplingParams(const SamplingParams(maxTokens: 100));
      await n.continueMessage(reply.id);

      s = c.read(chatControllerProvider(args)).value!;
      expect(s.messages.length, 2, reason: 'no new message row');
      expect(s.messages.last.id, reply.id);
      expect(s.messages.last.content, startsWith('a b a b '));
      expect(s.messages.last.status, MessageStatus.complete);
      // The engine saw the partial reply, then the continue instruction.
      final turns = engine.lastMessages!;
      expect(turns[turns.length - 2].role, EngineRole.assistant);
      expect(turns[turns.length - 2].content, 'a b ');
      expect(turns.last.role, EngineRole.user);
      expect(turns.last.content, contains('Continue'));
    });

    test('a user-stopped reply can be continued', () async {
      final (c, args, _) = await setup(
        tokens: List.filled(40, 'w '),
        tokenDelay: const Duration(milliseconds: 20),
      );
      final n = c.read(chatControllerProvider(args).notifier);
      final send = n.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await n.cancel();
      await send;

      var s = c.read(chatControllerProvider(args)).value!;
      final reply = s.messages.last;
      expect(reply.status, MessageStatus.cancelled);
      expect(reply.content, isNotEmpty);
      final before = reply.content.length;

      await n.continueMessage(reply.id);
      s = c.read(chatControllerProvider(args)).value!;
      expect(s.messages.last.id, reply.id);
      expect(s.messages.last.content.length, greaterThan(before));
      expect(s.messages.last.status, MessageStatus.complete);
    });

    test(
      'only the newest unfinished non-empty reply can be continued',
      () async {
        final (c, args, engine) = await setup();
        final n = c.read(chatControllerProvider(args).notifier);

        // Complete reply: nothing to continue.
        await n.sendMessage('one');
        var s = c.read(chatControllerProvider(args)).value!;
        expect(s.messages.last.status, MessageStatus.complete);
        final calls = engine.generateCount;
        await n.continueMessage(s.messages.last.id);
        expect(engine.generateCount, calls);

        // An older truncated reply is not the newest: no-op.
        await n.setSamplingParams(const SamplingParams(maxTokens: 2));
        await n.sendMessage('two');
        s = c.read(chatControllerProvider(args)).value!;
        final truncated = s.messages.last;
        expect(truncated.status, MessageStatus.truncated);
        await n.setSamplingParams(const SamplingParams(maxTokens: 100));
        await n.sendMessage('three');
        final calls2 = engine.generateCount;
        await n.continueMessage(truncated.id);
        expect(engine.generateCount, calls2);
      },
    );

    test('an errored reply with partial text keeps it visible and can be '
        'continued', () async {
      final (c, args, _) = await setup();
      final n = c.read(chatControllerProvider(args).notifier);
      await n.setSamplingParams(const SamplingParams(maxTokens: 2));
      await n.sendMessage('hi');
      final s = c.read(chatControllerProvider(args)).value!;
      final id = s.messages.last.id;
      // Simulate an error that struck after some text was written.
      await c
          .read(chatRepositoryProvider)
          .finalize(id, status: MessageStatus.error, errorKind: 'X');
      // Reopen the saved conversation, as after an app restart.
      final reopened = ChatRouteArgs(conversationId: s.conversationId);
      await c.read(chatControllerProvider(reopened).future);
      c.listen(chatControllerProvider(reopened), (_, _) {});
      var s2 = c.read(chatControllerProvider(reopened)).value!;
      expect(s2.messages.last.status, MessageStatus.error);
      expect(s2.messages.last.content, 'a b ');

      final n2 = c.read(chatControllerProvider(reopened).notifier);
      await n2.setSamplingParams(const SamplingParams(maxTokens: 100));
      await n2.continueMessage(id);
      s2 = c.read(chatControllerProvider(reopened)).value!;
      expect(s2.messages.last.content, startsWith('a b a b '));
      expect(s2.messages.last.status, MessageStatus.complete);
    });
  });

  group('D3 warm-up and first-token timeout', () {
    test(
      'warmingSince is set from send until the first token, then cleared',
      () async {
        final (c, args, _) = await setup(
          tokenDelay: const Duration(milliseconds: 80),
        );
        final n = c.read(chatControllerProvider(args).notifier);
        final send = n.sendMessage('hi');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        var s = c.read(chatControllerProvider(args)).value!;
        expect(s.warmingSince, isNotNull);
        expect(s.firstTokenTimedOut, isFalse);
        await send;
        s = c.read(chatControllerProvider(args)).value!;
        expect(s.warmingSince, isNull);
        expect(s.awaitingFirstToken, isFalse);
      },
    );

    test('no first token within the timeout flags it; Stop clears the flag '
        'and leaves a stopped reply', () async {
      final (c, args, _) = await setup(
        tokenDelay: const Duration(milliseconds: 600),
        firstTokenTimeout: const Duration(milliseconds: 150),
      );
      final n = c.read(chatControllerProvider(args).notifier);
      final send = n.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      var s = c.read(chatControllerProvider(args)).value!;
      expect(s.firstTokenTimedOut, isTrue);
      expect(s.awaitingFirstToken, isTrue);

      await n.cancel();
      await send;
      s = c.read(chatControllerProvider(args)).value!;
      expect(s.firstTokenTimedOut, isFalse);
      expect(s.warmingSince, isNull);
      expect(s.isGenerating, isFalse);
      expect(s.messages.last.status, MessageStatus.cancelled);
    });

    test('a first token that arrives in time never flags a timeout', () async {
      final (c, args, _) = await setup(
        firstTokenTimeout: const Duration(milliseconds: 200),
      );
      final n = c.read(chatControllerProvider(args).notifier);
      await n.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        c.read(chatControllerProvider(args)).value!.firstTokenTimedOut,
        isFalse,
      );
    });

    test('Try again stops the stuck turn and re-runs it', () async {
      final (c, args, engine) = await setup(
        tokenDelay: const Duration(milliseconds: 300),
        firstTokenTimeout: const Duration(milliseconds: 100),
      );
      final n = c.read(chatControllerProvider(args).notifier);
      final send = n.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        c.read(chatControllerProvider(args)).value!.firstTokenTimedOut,
        isTrue,
      );
      final retry = n.retryStalled();
      await send;
      // The retry starts a second generation on a fresh reply.
      await retry;
      expect(engine.generateCount, 2);
    });
  });
}
