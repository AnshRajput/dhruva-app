/// G1 exit gate ("voice loop works: audio in → transcript → chat → TTS
/// out, integration test") — Loop 6 QA adversarial pass.
///
/// The T1/T2 HANDOFFs each unit-test their own slice (VoiceInputController
/// against a FakeVoiceService/FakeMicSource; ChatController against a
/// FakeEngineService; VoicePlaybackController against a FakeVoiceService/
/// FakeAudioSink) but nothing exercises the WHOLE chain in one test: a
/// held mic buffer becomes a transcript, that transcript becomes a real
/// user chat message, a real `ChatController` drives a (fake) engine to a
/// streamed reply, and the reply text is the thing actually handed to
/// [VoiceService.synthesize] for playback. This file closes that gap.
///
/// Everything below the mic/speaker boundary is fake (FakeMicSource,
/// FakeVoiceService, FakeAudioSink, FakeEngineService) — that's the
/// documented, deliberate seam (native mic/audio/inference can't run under
/// `flutter test`). `ChatController` itself is real. The real STT↔TTS
/// round-trip on real sherpa_onnx is a separate, machine-gated concern
/// (`sherpa_voice_integration_test.dart`).
library;

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/voice/state/voice_input_controller.dart';
import 'package:dhruva/features/voice/state/voice_playback_controller.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
import 'package:dhruva/voice/fake_mic_source.dart';
import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/voice/voice_test_helpers.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late Directory tmp;
  late ProviderContainer container;
  late FakeMicSource mic;
  late FakeVoiceService voice;
  late FakeAudioSink sink;
  late FakeEngineService engine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('voice_loop_integration_');
    installAllVoiceModels(tmp);
    mic = FakeMicSource();
    voice = FakeVoiceService(
      scriptedTranscript: 'what is the capital of france',
    );
    sink = FakeAudioSink();
    engine = FakeEngineService(
      scriptedTokens: const ['Paris', ' is', ' the', ' capital', '.'],
      tokenDelay: const Duration(milliseconds: 5),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
        ),
        voiceServiceProvider.overrideWithValue(voice),
        micSourceProvider.overrideWithValue(mic),
        audioSinkProvider.overrideWithValue(sink),
      ],
    );
    container.listen(voiceInputControllerProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<int> insertModel() {
    return db
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
  }

  test('G1: hold-to-talk audio -> transcript -> chat message -> engine reply '
      '-> TTS synthesize invoked on the reply', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    final chat = container.read(chatControllerProvider(args).notifier);

    // 1. Audio in -> transcript (hold-to-talk).
    final inputNotifier = container.read(voiceInputControllerProvider.notifier);
    await inputNotifier.startHold();
    expect(
      container.read(voiceInputControllerProvider).phase,
      VoiceInputPhase.listening,
    );
    mic.pushSpeech();
    mic.pushSilence();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final finalText = await inputNotifier.endHold();
    expect(finalText, 'what is the capital of france');
    expect(voice.transcribeCount, 1);

    // 2. Transcript -> chat message -> engine streams a reply (real
    // ChatController, fake engine).
    await chat.sendMessage(finalText);
    final chatState = container.read(chatControllerProvider(args)).value!;
    expect(chatState.messages, hasLength(2));
    expect(chatState.messages.first.content, finalText);
    final assistant = chatState.messages.last;
    expect(assistant.content, 'Paris is the capital.');
    expect(assistant.status, MessageStatus.complete);

    // 3. Reply -> TTS synthesize invoked on exactly that text.
    final playback = container.read(voicePlaybackControllerProvider.notifier);
    await playback.toggle(assistant.id, assistant.content);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(voice.synthesizeCount, 1);
    expect(voice.lastSynthesizedText, 'Paris is the capital.');
    expect(sink.playCount, 1);
    expect(
      container.read(voicePlaybackControllerProvider).isPlaying(assistant.id),
      isTrue,
    );
  });

  test('G1 negative control: an unrelated reply text is never handed to '
      'synthesize (proves the chain is wired end-to-end, not just both ends '
      'independently working)', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    await container.read(chatControllerProvider(args).future);
    container.listen(chatControllerProvider(args), (_, _) {});
    final chat = container.read(chatControllerProvider(args).notifier);

    final inputNotifier = container.read(voiceInputControllerProvider.notifier);
    await inputNotifier.startHold();
    mic.pushSpeech();
    mic.pushSilence();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final finalText = await inputNotifier.endHold();
    await chat.sendMessage(finalText);
    final assistant = container
        .read(chatControllerProvider(args))
        .value!
        .messages
        .last;

    final playback = container.read(voicePlaybackControllerProvider.notifier);
    await playback.toggle(assistant.id, assistant.content);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(voice.lastSynthesizedText, isNot('what is the capital of france'));
    expect(voice.lastSynthesizedText, assistant.content);
  });
}
