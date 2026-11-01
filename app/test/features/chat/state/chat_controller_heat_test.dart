// Battery & heat guard wiring in ChatController: a critical thermal reading
// stops the reply but keeps the partial text; polling runs only during a
// generation; a guard that is switched off never stops anything.

import 'package:dhruva/core/device_health/device_health.dart';
import 'package:dhruva/core/device_health/device_health_provider.dart';
import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
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

  Future<(ProviderContainer, ChatRouteArgs, FakeHealthService)> setup({
    required ThermalLevel thermal,
    bool guardOn = true,
  }) async {
    final health = FakeHealthService(
      DeviceHealth(batteryPercent: 80, thermal: thermal),
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(
          FakeEngineService(
            scriptedTokens: List.filled(60, 'word '),
            tokenDelay: const Duration(milliseconds: 40),
          ),
        ),
        deviceHealthServiceProvider.overrideWithValue(health),
        deviceGuardStoreProvider.overrideWith(
          (ref) async => MemoryGuardStore(enabled: guardOn),
        ),
        deviceHealthPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 30),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(deviceHealthProvider); // loads the guard switch
    await container.read(deviceGuardEnabledProvider.future);
    final args = ChatRouteArgs(initialModelId: await insertModel());
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    return (container, args, health);
  }

  test(
    'already critical when the reply starts: stopped straight away',
    () async {
      final (c, args, _) = await setup(thermal: ThermalLevel.critical);
      await c.read(chatControllerProvider(args).notifier).sendMessage('hi');

      final state = c.read(chatControllerProvider(args)).value!;
      expect(state.messages.last.status, MessageStatus.cancelled);
      expect(state.heatStoppedMessageIds, {state.messages.last.id});
    },
  );

  test('critical thermal mid-reply stops it, keeps partial text, marks it, '
      'and stops polling', () async {
    final (c, args, health) = await setup(thermal: ThermalLevel.nominal);
    final notifier = c.read(chatControllerProvider(args).notifier);

    Future<void>.delayed(
      const Duration(milliseconds: 400),
      () => health.next = const DeviceHealth(
        batteryPercent: 80,
        thermal: ThermalLevel.critical,
      ),
    );
    await notifier.sendMessage('hi');

    final state = c.read(chatControllerProvider(args)).value!;
    final reply = state.messages.last;
    expect(reply.status, MessageStatus.cancelled);
    expect(reply.content, isNotEmpty);
    // A full reply would be 60 tokens x 5 chars = 300.
    expect(reply.content.length, lessThan(300));
    expect(state.heatStoppedMessageIds, {reply.id});
    expect(state.isGenerating, isFalse);
    expect(c.read(deviceHealthProvider.notifier).isPolling, isFalse);

    final reads = health.reads;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(health.reads, reads, reason: 'no polling when idle');
  });

  test('serious thermal never stops the reply', () async {
    final (c, args, _) = await setup(thermal: ThermalLevel.serious);
    final notifier = c.read(chatControllerProvider(args).notifier);

    await notifier.sendMessage('hi');

    final state = c.read(chatControllerProvider(args)).value!;
    expect(state.messages.last.status, MessageStatus.complete);
    expect(state.heatStoppedMessageIds, isEmpty);
  });

  test('guard off: critical thermal is ignored and nothing polls', () async {
    final (c, args, health) = await setup(
      thermal: ThermalLevel.critical,
      guardOn: false,
    );
    final notifier = c.read(chatControllerProvider(args).notifier);

    await notifier.sendMessage('hi');

    final state = c.read(chatControllerProvider(args)).value!;
    expect(state.messages.last.status, MessageStatus.complete);
    expect(state.heatStoppedMessageIds, isEmpty);
    expect(health.reads, 0);
  });
}
