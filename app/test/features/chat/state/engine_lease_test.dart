// H1: the engine lease is real. Chat outranks background users (brief writer,
// inbox summarizer): it never meets "busy", never starts a second load, and
// background work never starts while chat has the engine.

import 'dart:async';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/di/speed_providers.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/state/engine_session.dart';
import 'package:dhruva/features/inbox/state/inbox_summarizer.dart';
import 'package:dhruva/features/today/state/brief_writer.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_health_fakes.dart';

const _deviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertModel() => db
      .into(db.installedModels)
      .insert(
        InstalledModelsCompanion.insert(
          repoId: 'org/model',
          fileName: 'model.gguf',
          sizeBytes: 100,
          localPath: '/tmp/dhruva-test-model.gguf',
          downloadedAt: DateTime.utc(2026, 11, 1),
        ),
      );

  ProviderContainer build(FakeEngineService engine) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_deviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        ...deviceHealthTestOverrides(),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<ConnectorItem> seedNotification(ProviderContainer c) async {
    final store = c.read(connectorStoreProvider);
    await store.saveAccount('notifications');
    await store.upsertItems('notifications', [
      ItemDraft(
        externalId: '1',
        kind: ItemKind.notification,
        title: 'Slack',
        body: 'Sana wants notes on onboarding',
        sentAt: DateTime.now(),
        flags: const {'pkg': 'a', 'app': 'Slack'},
      ),
    ]);
    return (await store.itemsOf('notifications')).single;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group('LoadGate / engine.load', () {
    test('concurrent loads never overlap (no double isolate spawn)', () async {
      final engine = FakeEngineService(
        loadDelay: const Duration(milliseconds: 40),
      );
      await Future.wait([
        engine.load('/m/a.gguf'),
        engine.load('/m/b.gguf'),
        engine.load('/m/c.gguf'),
      ]);
      expect(engine.maxConcurrentLoads, 1);
      expect(engine.loadCount, 3);
      expect(engine.lastLoadParams, isNotNull);
    });

    test('identical concurrent loads share one future', () async {
      final engine = FakeEngineService(
        loadDelay: const Duration(milliseconds: 40),
      );
      await Future.wait([engine.load('/m/a.gguf'), engine.load('/m/a.gguf')]);
      expect(engine.loadCount, 1);
      expect(engine.maxConcurrentLoads, 1);
    });

    test('a failed load does not poison the queue behind it', () async {
      final gate = LoadGate();
      final first = gate.run('a', () async => throw StateError('boom'));
      final second = gate.run('b', () async {});
      await expectLater(first, throwsStateError);
      await second;
      await gate.idle();
    });
  });

  group('EngineLease', () {
    test('background is refused while chat or a speed test is busy', () {
      final lease = EngineLease();
      lease.chatEnter();
      expect(lease.tryEnterBackground(() {}), isNull);
      lease.chatLeave();
      final hold = lease.tryEnterBackground(() {});
      expect(hold, isNotNull);
      expect(lease.tryEnterBackground(() {}), isNull, reason: 'one at a time');
      hold!.release();
      expect(lease.tryStartSpeedTest(), isTrue);
      expect(lease.tryEnterBackground(() {}), isNull);
    });

    test(
      'preemptBackground signals the holder and waits for release',
      () async {
        final lease = EngineLease();
        var preempted = 0;
        late BackgroundHold hold;
        hold = lease.tryEnterBackground(() {
          preempted++;
          Timer(const Duration(milliseconds: 50), hold.release);
        })!;
        lease.chatEnter();
        final sw = Stopwatch()..start();
        await lease.preemptBackground();
        expect(preempted, 1);
        expect(hold.preempted, isTrue);
        expect(lease.backgroundBusy, isFalse);
        expect(sw.elapsedMilliseconds, lessThan(900));
      },
    );

    test(
      'a holder that never lets go cannot block chat past the grace',
      () async {
        final lease = EngineLease();
        lease.tryEnterBackground(() {});
        lease.chatEnter();
        final sw = Stopwatch()..start();
        await lease.preemptBackground(grace: const Duration(milliseconds: 100));
        expect(sw.elapsedMilliseconds, lessThan(500));
      },
    );
  });

  group('scenarios from the Wave 4 gate', () {
    test('A: summarizer inside engine.load, user sends: one load, no error, '
        'chat answers', () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: const ['Hello', ' world'],
        tokenDelay: const Duration(milliseconds: 5),
        loadDelay: const Duration(milliseconds: 400),
      );
      final c = build(engine);
      final item = await seedNotification(c);
      final summarizer = c.read(inboxSummarizerProvider);
      summarizer.request(item);
      await until(() => c.read(engineLeaseProvider).backgroundBusy);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.isLoaded, isFalse, reason: 'summarizer still loading');

      final args = ChatRouteArgs(initialModelId: modelId);
      await c.read(chatControllerProvider(args).future);
      c.listen(chatControllerProvider(args), (_, _) {});
      final notifier = c.read(chatControllerProvider(args).notifier);
      await notifier.sendMessage('hi');

      final state = c.read(chatControllerProvider(args)).value!;
      expect(state.modelLoadError, isNull);
      expect(state.messages.last.status, MessageStatus.complete);
      expect(state.messages.last.content, 'Hello world');
      expect(engine.maxConcurrentLoads, 1);
      expect(summarizer.done, isEmpty, reason: 'it yielded, not wrote');
    });

    test('B: brief prepare() racing a chat send never double-loads and never '
        'blocks chat', () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: const ['Hi'],
        tokenDelay: const Duration(milliseconds: 5),
        loadDelay: const Duration(milliseconds: 150),
      );
      final c = build(engine);
      final writer = c.read(briefWriterProvider);
      // Starts, and is awaiting the model list when chat sends.
      final prepare = writer.prepare().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      final args = ChatRouteArgs(initialModelId: modelId);
      await c.read(chatControllerProvider(args).future);
      c.listen(chatControllerProvider(args), (_, _) {});
      await c.read(chatControllerProvider(args).notifier).sendMessage('hi');
      final outcome = await prepare;

      final state = c.read(chatControllerProvider(args)).value!;
      expect(state.modelLoadError, isNull);
      expect(state.messages.last.status, MessageStatus.complete);
      expect(engine.maxConcurrentLoads, 1);
      expect(outcome == null || outcome is BriefUnavailable, isTrue);
    });

    test('C: a background generate in flight when the user sends is cancelled '
        'within ~1 s; chat gets no "already in flight" error', () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: List.filled(200, 'x'),
        tokenDelay: const Duration(milliseconds: 20),
      );
      final c = build(engine);
      await engine.load('/tmp/dhruva-test-model.gguf');
      // The chat model is already resident: chat has no reload to hide behind.
      c.read(loadedModelIdProvider.notifier).set(modelId);
      final item = await seedNotification(c);
      final summarizer = c.read(inboxSummarizerProvider);
      summarizer.request(item);
      await until(() => engine.generateCount > 0);
      expect(engine.generateCount, 1);

      final args = ChatRouteArgs(initialModelId: modelId);
      await c.read(chatControllerProvider(args).future);
      c.listen(chatControllerProvider(args), (_, _) {});
      final notifier = c.read(chatControllerProvider(args).notifier);
      final sw = Stopwatch()..start();
      final send = notifier.sendMessage('hi');
      await until(() => engine.generateCount > 1);
      expect(
        sw.elapsedMilliseconds,
        lessThan(1500),
        reason: 'background yielded fast',
      );
      await send;

      final state = c.read(chatControllerProvider(args)).value!;
      expect(state.messages.last.status, MessageStatus.complete);
      expect(state.messages.last.errorKind, isNull);
      expect(summarizer.done, isEmpty);
    });

    test('background never starts while chat is generating', () async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: List.filled(30, 'y'),
        tokenDelay: const Duration(milliseconds: 20),
      );
      final c = build(engine);
      final item = await seedNotification(c);
      final args = ChatRouteArgs(initialModelId: modelId);
      await c.read(chatControllerProvider(args).future);
      c.listen(chatControllerProvider(args), (_, _) {});
      final send = c
          .read(chatControllerProvider(args).notifier)
          .sendMessage('hi');
      await until(() => engine.generateCount > 0);
      final before = engine.generateCount;
      c.read(inboxSummarizerProvider).request(item);
      final brief = await c
          .read(briefWriterProvider)
          .write(system: 's', prompt: 'p')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(brief, isA<BriefUnavailable>());
      expect(engine.generateCount, before, reason: 'no second generate');
      await send;
    });
  });

  group('H2: summarizer only while the Inbox is visible', () {
    test('hidden inbox: nothing runs; visible again: it resumes', () async {
      await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: const ['"A ', 'summary."'],
        tokenDelay: Duration.zero,
      );
      final c = build(engine);
      final item = await seedNotification(c);
      final s = c.read(inboxSummarizerProvider);
      final screen = Object();
      s.setVisible(screen, false); // the tab is off screen
      s.request(item);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(engine.generateCount, 0);
      expect(engine.loadCount, 0);
      s.setVisible(screen, true);
      await until(() => s.done.isNotEmpty);
      expect(s.done, [item.id]);
      s.forget(screen);
    });
  });
}
