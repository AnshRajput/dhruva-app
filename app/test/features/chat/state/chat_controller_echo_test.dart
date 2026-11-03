import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/connector_providers.dart'
    show liveConnectorIdsProvider;
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/data/connectors/sources_block.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/answer_guard.dart';
import 'package:dhruva/features/chat/state/ask_selection.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/state/repetition_guard.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

// What a 0.5B model does with the grounded prompt: it repeats the preamble and
// the numbered rows instead of answering.
final _dump = [
  '$sourcesPreamble\n',
  '<sources>\n',
  '[1] event | Budget review | ',
  'Mon 9:00\n',
  '[2] contact | Ravi Kumar | ',
  'ravi@example.com\n',
  '[3] event | Budget review',
  ' again',
];

void main() {
  late AppDatabase db;
  late ConnectorStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = ConnectorStore(db: db);
    await store.saveAccount('calendar');
    await store.upsertItems('calendar', [
      ItemDraft(
        externalId: 'e1',
        kind: ItemKind.event,
        title: 'Budget review',
        startsAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    ]);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  Future<(ProviderContainer, ChatController, ChatRouteArgs)> boot(
    FakeEngineService engine, {
    SamplingParams? sampling,
  }) async {
    final modelId = await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Some-Model-GGUF',
            fileName: 'model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-echo-test.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        liveConnectorIdsProvider.overrideWith(
          (ref) async => const {'calendar'},
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(chatControllerProvider(args).future);
    c.listen(chatControllerProvider(args), (_, _) {});
    c.listen(askSelectionProvider(args), (_, _) {});
    final ctrl = c.read(chatControllerProvider(args).notifier);
    if (sampling != null) await ctrl.setSamplingParams(sampling);
    return (c, ctrl, args);
  }

  Future<void> expectNotice(
    ProviderContainer c,
    ChatRouteArgs args,
    List<String> shown,
  ) async {
    final s = c.read(chatControllerProvider(args)).value!;
    final reply = s.messages.last;
    expect(reply.content, echoNotice);
    expect(reply.status, MessageStatus.complete);
    expect(reply.itemSources, isNotEmpty);
    // The raw scaffold never reached the thread, not even while streaming.
    for (final t in shown) {
      expect(t, isNot(contains('<sources>')));
      expect(t, isNot(contains('[1] event')));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stored = await ChatRepository(db: db).getMessages(s.conversationId!);
    expect(stored.last.content, echoNotice);
    expect(stored.last.status, MessageStatus.complete);
  }

  List<String> watch(ProviderContainer c, ChatRouteArgs args) {
    final shown = <String>[];
    c.listen(chatControllerProvider(args), (_, next) {
      final m = next.value?.messages.lastOrNull;
      if (m != null && m.role == MessageRole.assistant) shown.add(m.content);
    });
    return shown;
  }

  test('a complete echo is replaced by the notice, chips kept', () async {
    final (c, ctrl, args) = await boot(
      FakeEngineService(
        scriptedTokens: _dump,
        tokenDelay: const Duration(milliseconds: 5),
      ),
    );
    final shown = watch(c, args);
    await ctrl.sendMessage('What meetings do I have today?');
    await expectNotice(c, args, shown);
  });

  test('an echo cut off at maxTokens is replaced too', () async {
    final (c, ctrl, args) = await boot(
      FakeEngineService(
        scriptedTokens: _dump,
        tokenDelay: const Duration(milliseconds: 1),
      ),
      sampling: const SamplingParams(maxTokens: 5),
    );
    final shown = watch(c, args);
    await ctrl.sendMessage('What meetings do I have today?');
    await expectNotice(c, args, shown);
  });

  test('an echo the user stops mid-dump is replaced too', () async {
    final (c, ctrl, args) = await boot(
      FakeEngineService(
        scriptedTokens: _dump,
        tokenDelay: const Duration(milliseconds: 20),
      ),
    );
    final shown = watch(c, args);
    final send = ctrl.sendMessage('What meetings do I have today?');
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await ctrl.cancel();
    await send;
    await expectNotice(c, args, shown);
  });

  test('a streaming echo is swapped live and generation is stopped', () async {
    final engine = FakeEngineService(
      scriptedTokens: [..._dump, ...List.filled(40, ' more')],
      tokenDelay: const Duration(milliseconds: 20),
    );
    final (c, ctrl, args) = await boot(engine);
    final shown = watch(c, args);
    await ctrl.sendMessage('What meetings do I have today?');
    await expectNotice(c, args, shown);
    expect(shown, contains(echoNotice));
  });

  test('a looped grounded answer is a retryable error with no chips', () async {
    final (c, ctrl, args) = await boot(
      FakeEngineService(
        scriptedTokens: const [
          '[1]. Ana Costa is an individual with a valid contact phone ',
          'number provided by Ana Costa, Ana Costa, with Ana Costa, ',
          'with Ana Costa.',
        ],
        tokenDelay: const Duration(milliseconds: 5),
      ),
    );
    await ctrl.sendMessage('What meetings do I have today?');
    final reply = c.read(chatControllerProvider(args)).value!.messages.last;
    expect(reply.status, MessageStatus.error);
    expect(reply.errorKind, degenerateErrorKind);
    expect(reply.content, isEmpty);
    expect(reply.itemSources, isEmpty);
  });

  test('a streaming loop is cut off and never shown', () async {
    final (c, ctrl, args) = await boot(
      FakeEngineService(
        scriptedTokens: List.filled(60, 'the budget review is at nine '),
        tokenDelay: const Duration(milliseconds: 20),
      ),
    );
    final shown = watch(c, args);
    await ctrl.sendMessage('What meetings do I have today?');
    final reply = c.read(chatControllerProvider(args)).value!.messages.last;
    expect(reply.errorKind, degenerateErrorKind);
    expect(shown.where((t) => t.length > 150), isEmpty);
  });

  test('a grounded turn samples cool, capped, with a repeat penalty', () async {
    final engine = FakeEngineService(
      scriptedTokens: const ['Budget review is at 9:00 ', '[1].'],
      tokenDelay: const Duration(milliseconds: 5),
    );
    final (_, ctrl, _) = await boot(engine);
    await ctrl.sendMessage('What meetings do I have today?');
    final p = engine.lastParams!;
    expect(p.temperature, lessThanOrEqualTo(0.3));
    expect(p.maxTokens, lessThanOrEqualTo(320));
    expect(p.repeatPenalty, 1.1);
    expect(p.penaltyLastN, 64);
  });

  test('a real answer is left alone', () async {
    final (c, ctrl, args) = await boot(
      FakeEngineService(
        scriptedTokens: const ['Budget review is at 9:00 ', '[1].'],
        tokenDelay: const Duration(milliseconds: 5),
      ),
    );
    await ctrl.sendMessage('What meetings do I have today?');
    final reply = c.read(chatControllerProvider(args)).value!.messages.last;
    expect(reply.content, 'Budget review is at 9:00 [1].');
  });
}
