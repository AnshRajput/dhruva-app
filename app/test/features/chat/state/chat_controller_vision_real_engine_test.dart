// Loop 7 T7 "real check": image -> question -> answer driven through the
// REAL ChatController + real LlamaEngineService + real SmolVLM-500M + its
// mmproj projector (not FakeEngineService) — proves the whole wiring this
// loop built (mmprojPath load path, isMultimodal gate, ChatTurn.images
// plumbing, attachedImages render map) round-trips against T1's actual
// multimodal engine, not just the fake. Same skip-if-absent pattern as
// chat_controller_real_engine_test.dart / engine_vision_test.dart.

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart'
    show AppDatabase, InstalledModelsCompanion;
import 'package:dhruva/engine_bindings/llama_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../native_test_config.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  final v = resolveVisionPaths();
  final skip = v == null
      ? 'vision artifacts absent (dylib/model/mmproj)'
      : false;

  test(
    'image -> question -> grounded answer through the real ChatController '
    '(mmprojPath load path + isMultimodal gate + ChatTurn.images, gate G1)',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final engine = LlamaEngineService(libraryPath: v!.libraryPath);
      addTearDown(engine.dispose);

      final modelId = await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'local/SmolVLM-500M-Instruct',
              fileName: 'SmolVLM-500M-Instruct-Q8_0.gguf',
              sizeBytes: File(v.modelPath).lengthSync(),
              localPath: v.modelPath,
              downloadedAt: DateTime.now(),
              mmprojPath: Value(v.mmprojPath),
              isVision: const Value(true),
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
      // B1 (autoDispose): keeps the provider alive across the bare
      // ensureModelLoaded() call below, same as chat_controller_test.dart's
      // convention — without a listener, nothing holds it open between
      // reads in a widget-less container test.
      container.listen(chatControllerProvider(args), (_, _) {});
      final notifier = container.read(chatControllerProvider(args).notifier);

      // Confirms the mmprojPath load path + isMultimodal gate BEFORE
      // sending — the same signal composer.dart's attach button gates on.
      await notifier.ensureModelLoaded();
      expect(
        container.read(chatControllerProvider(args)).value!.isMultimodal,
        isTrue,
        reason: 'mmprojPath did not reach EngineLoadParams / engine.load',
      );

      final imageBytes = await File('test/assets/red_64.png').readAsBytes();
      await notifier.sendMessage(
        'What is the main color of this image? Answer in one short '
        'sentence.',
        imageBytes: imageBytes,
      );

      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.modelLoadError, isNull);
      final assistant = state.messages.last;
      // ignore: avoid_print
      print(
        'VISION CHAT ANSWER (red_64.png via real ChatController): '
        '"${assistant.content}"',
      );
      expect(assistant.content.trim(), isNotEmpty);
      expect(assistant.status.toString(), contains('complete'));
      expect(
        assistant.content.toLowerCase(),
        contains('red'),
        reason:
            'answer did not reference the red image: "${assistant.content}"',
      );
      // The image rendered in the user bubble's data (chat_thread_screen.
      // dart reads this map to show the thumbnail).
      expect(state.attachedImages[state.messages.first.id], imageBytes);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
