// Loop 5 MVP-style real-engine check (macOS build machine): the brief's
// [D2]/[G1] evidence requirement — start a chat with a distinctive character
// (a pirate persona) and a neutral one (no persona at all), same prompt,
// real SmolLM2, and confirm the persona visibly changes the reply. Skips
// when the dev-native dylib/GGUF are absent (see native_test_config.dart),
// matching every other real-engine test's pattern.
//
// This is evidence, not a strict behavioral assertion: a 135M model's
// persona adherence isn't something to hard-assert word-for-word, so the
// test prints both full replies for manual/report inspection and only
// soft-asserts the two replies differ (near-certain given different system
// prompts, even before considering sampling randomness) as a canary against
// a completely broken persona pipe. The persona itself is a strong lexical/
// stylistic instruction ("always speak like a pirate"), not a negation
// ("never discuss X") — small models follow "speak like this" far more
// reliably than "don't do that," so the printed transcript is a fair,
// eyeball-checkable demonstration rather than one relying on weak negation
// instruction-following.

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/data/db/database.dart';
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

const _prompt = 'Tell me about your day.';
const _piratePersona =
    'You are Captain Byte, a swashbuckling pirate captain. You ALWAYS speak '
    "in heavy pirate slang — 'arr', 'matey', 'shiver me timbers', "
    "'ye'/'yer' instead of 'you'/'your' — in every single sentence, no "
    'exceptions, no matter what is asked.';

void main() {
  final paths = resolveNativePaths();
  final skip = paths == null
      ? 'native artifacts absent (dylib and/or GGUF)'
      : false;

  test(
    'MVP evidence: a persona-bound conversation visibly answers differently '
    'than a neutral one, real engine + real SmolLM2',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final engine = LlamaEngineService(libraryPath: paths!.libraryPath);
      addTearDown(engine.dispose);

      final modelId = await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'local/SmolLM2-135M-Instruct',
              fileName: 'SmolLM2-135M-Instruct-Q4_K_M.gguf',
              sizeBytes: File(paths.modelPath).lengthSync(),
              localPath: paths.modelPath,
              downloadedAt: DateTime.now(),
            ),
          );

      final now = DateTime.now();
      const sampling = SamplingParams(temperature: 0.2, seed: 7);
      final characterId = await db
          .into(db.characters)
          .insert(
            CharactersCompanion.insert(
              name: 'Captain Byte',
              personaSystemPrompt: _piratePersona,
              samplingParamsJson: Value(jsonEncode(sampling.toJson())),
              createdAt: now,
              updatedAt: now,
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

      // ---- neutral: an ordinary conversation, no persona ----
      final neutralArgs = ChatRouteArgs(initialModelId: modelId);
      await container.read(chatControllerProvider(neutralArgs).future);
      await container
          .read(chatControllerProvider(neutralArgs).notifier)
          .setSamplingParams(sampling);
      final neutralNotifier = container.read(
        chatControllerProvider(neutralArgs).notifier,
      );
      await neutralNotifier.sendMessage(_prompt);
      final neutralReply = container
          .read(chatControllerProvider(neutralArgs))
          .value!
          .messages
          .last
          .content;

      // ---- persona: Captain Byte the pirate, same prompt ----
      final personaArgs = ChatRouteArgs(
        initialModelId: modelId,
        characterId: characterId,
      );
      await container.read(chatControllerProvider(personaArgs).future);
      final personaNotifier = container.read(
        chatControllerProvider(personaArgs).notifier,
      );
      await personaNotifier.sendMessage(_prompt);
      final personaReply = container
          .read(chatControllerProvider(personaArgs))
          .value!
          .messages
          .last
          .content;

      // ignore: avoid_print
      print(
        'MVP EVIDENCE (Loop 5, prompt: "$_prompt")\n'
        '  neutral (no persona)      -> "$neutralReply"\n'
        '  Captain Byte (persona)    -> "$personaReply"',
      );

      expect(neutralReply.trim(), isNotEmpty);
      expect(personaReply.trim(), isNotEmpty);
      expect(
        personaReply,
        isNot(equals(neutralReply)),
        reason:
            'the persona system prompt should visibly change the reply — '
            'identical output across two different system prompts would '
            'mean the persona never reached the engine',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
