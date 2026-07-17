import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/features/voice/state/voice_input_controller.dart';
import 'package:dhruva/voice/fake_mic_source.dart';
import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../voice_test_helpers.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;
  late FakeMicSource mic;
  late FakeVoiceService voice;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('voice_input_test_');
    mic = FakeMicSource();
    voice = FakeVoiceService(scriptedTranscript: 'hello world');
    container = ProviderContainer(
      overrides: [
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
        ),
        voiceServiceProvider.overrideWithValue(voice),
        micSourceProvider.overrideWithValue(mic),
      ],
    );
    // `voiceInputControllerProvider` is `.autoDispose` — without an active
    // listener it can be torn down between `container.read()` calls (same
    // precedent as `chat_controller_test.dart`).
    container.listen(voiceInputControllerProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('no voice models installed -> noModel, mic never opened', () async {
    final notifier = container.read(voiceInputControllerProvider.notifier);
    await notifier.startHold();

    expect(
      container.read(voiceInputControllerProvider).phase,
      VoiceInputPhase.noModel,
    );
    expect(mic.startCount, 0);
  });

  test(
    'models installed but mic permission denied -> permissionDenied',
    () async {
      installAllVoiceModels(tmp);
      mic.permissionGranted = false;
      final notifier = container.read(voiceInputControllerProvider.notifier);
      await notifier.startHold();

      expect(
        container.read(voiceInputControllerProvider).phase,
        VoiceInputPhase.permissionDenied,
      );
    },
  );

  test(
    'hold-to-talk: live transcript renders while held, release finalizes it',
    () async {
      installAllVoiceModels(tmp);
      final notifier = container.read(voiceInputControllerProvider.notifier);

      await notifier.startHold();
      expect(
        container.read(voiceInputControllerProvider).phase,
        VoiceInputPhase.listening,
      );
      expect(mic.startCount, 1);
      expect(container.read(voiceInputControllerProvider).liveText, isEmpty);

      // One closed utterance while still held -> live transcript grows.
      mic.pushSpeech();
      mic.pushSilence();
      await pump();
      expect(
        container.read(voiceInputControllerProvider).liveText,
        'hello world',
      );
      expect(
        container.read(voiceInputControllerProvider).phase,
        VoiceInputPhase.listening,
        reason: 'still held — release hasn\'t happened yet',
      );

      final finalText = await notifier.endHold();
      expect(finalText, 'hello world');
      expect(mic.stopCount, 1);
      expect(
        container.read(voiceInputControllerProvider).phase,
        VoiceInputPhase.idle,
      );
      expect(container.read(voiceInputControllerProvider).liveText, isEmpty);
    },
  );

  test('silence-only hold finalizes to empty text, not stuck', () async {
    installAllVoiceModels(tmp);
    final notifier = container.read(voiceInputControllerProvider.notifier);
    await notifier.startHold();

    mic.pushSilence();
    await pump();

    final finalText = await notifier.endHold();
    expect(finalText, isEmpty);
    expect(
      container.read(voiceInputControllerProvider).phase,
      VoiceInputPhase.idle,
    );
  });
}
