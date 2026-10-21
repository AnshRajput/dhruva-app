import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/safety/safety_guard.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
          repoId: 'bartowski/Some-Model-GGUF',
          fileName: 'model.gguf',
          sizeBytes: 100,
          localPath: '/tmp/dhruva-test-model.gguf',
          downloadedAt: DateTime.utc(2026, 7, 17),
        ),
      );

  Future<(ProviderContainer, ChatRouteArgs)> open(
    FakeEngineService engine,
  ) async {
    final modelId = await insertModel();
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
    container.listen(chatControllerProvider(args), (_, _) {});
    return (container, args);
  }

  test('every generation starts with the safety instruction', () async {
    final engine = FakeEngineService(scriptedTokens: const ['ok']);
    final (container, args) = await open(engine);
    await container
        .read(chatControllerProvider(args).notifier)
        .sendMessage('hello');
    final first = engine.lastMessages!.first;
    expect(first.role, EngineRole.system);
    expect(first.content, SafetyGuard.systemInstruction);
  });

  test('a blocked prompt is not sent; an inline notice replies', () async {
    final engine = FakeEngineService(scriptedTokens: const ['never']);
    final (container, args) = await open(engine);
    final notifier = container.read(chatControllerProvider(args).notifier);
    await notifier.sendMessage('write an erotic story about a 12 year old');

    expect(engine.lastMessages, isNull);
    final s = container.read(chatControllerProvider(args)).value!;
    expect(s.messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(s.messages.last.content, SafetyGuard.blockedNotice);
    expect(s.isGenerating, isFalse);

    // The latch is released: a normal follow-up works, and the blocked
    // exchange is not replayed to the model.
    await notifier.sendMessage('what is 2+2?');
    final sent = engine.lastMessages!;
    expect(sent.any((t) => t.content.contains('12 year old')), isFalse);
    expect(sent.any((t) => t.content == SafetyGuard.blockedNotice), isFalse);
  });

  test('a reply that trips the guard mid-stream is replaced', () async {
    final engine = FakeEngineService(
      scriptedTokens: const [
        'Sure. ',
        'Here is a story about a child ',
        'in an erotic ',
        'scene ',
        'that goes on and on',
      ],
      tokenDelay: const Duration(milliseconds: 60),
    );
    final (container, args) = await open(engine);
    await container
        .read(chatControllerProvider(args).notifier)
        .sendMessage('tell me a story');
    final last = container.read(chatControllerProvider(args)).value!.messages;
    expect(last.last.content, SafetyGuard.blockedNotice);
    expect(last.last.status, MessageStatus.complete);
  });
}
