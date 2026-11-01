// About me reaches the model: the system turn carries the "About the user"
// block (after the safety instruction) only when the user filled something in.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/profile/user_profile.dart';
import 'package:dhruva/core/safety/safety_guard.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
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

  Future<String> systemTurnWith(MemoryPrefsStore prefs) async {
    final modelId = await db
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
    final engine = FakeEngineService(scriptedTokens: const ['ok']);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        prefsStoreProvider.overrideWith((ref) async => prefs),
        ...deviceHealthTestOverrides(),
      ],
    );
    addTearDown(container.dispose);
    final args = ChatRouteArgs(initialModelId: modelId);
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    // The app warms this at startup (main.dart); the controller keeps it.
    await container.read(userContextProvider.future);
    await container
        .read(chatControllerProvider(args).notifier)
        .sendMessage('hello');
    return engine.lastMessages!.first.content;
  }

  test('an empty profile leaves the system turn untouched', () async {
    expect(
      await systemTurnWith(MemoryPrefsStore()),
      SafetyGuard.systemInstruction,
    );
  });

  test('a saved profile is appended after the safety instruction', () async {
    final system = await systemTurnWith(
      MemoryPrefsStore({
        'user_profile':
            '{"name":"Asha","role":"nurse","tone":"Short","signature":""}',
      }),
    );
    expect(system, startsWith(SafetyGuard.systemInstruction));
    expect(system, contains('About the user'));
    expect(system, contains('- Name: Asha'));
    expect(
      system.length,
      lessThan(SafetyGuard.systemInstruction.length + maxUserContextChars + 4),
    );
  });
}
