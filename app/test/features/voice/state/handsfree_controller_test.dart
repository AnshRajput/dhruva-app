import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/features/voice/state/handsfree_controller.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
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
  late FakeAudioSink sink;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('handsfree_test_');
    installAllVoiceModels(tmp);
    mic = FakeMicSource();
    voice = FakeVoiceService(scriptedTranscript: 'turn on the lights');
    sink = FakeAudioSink();
    container = ProviderContainer(
      overrides: [
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
        ),
        voiceServiceProvider.overrideWithValue(voice),
        micSourceProvider.overrideWithValue(mic),
        audioSinkProvider.overrideWithValue(sink),
      ],
    );
    // `handsFreeControllerProvider` is `.autoDispose` — keep it alive for
    // the test's duration (same precedent as `chat_controller_test.dart`).
    container.listen(handsFreeControllerProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('missing a voice model -> noModel phase, mic never opened', () async {
    final emptyTmp = Directory.systemTemp.createTempSync('handsfree_empty_');
    addTearDown(() => emptyTmp.deleteSync(recursive: true));
    final emptyContainer = ProviderContainer(
      overrides: [
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: emptyTmp),
        ),
        voiceServiceProvider.overrideWithValue(FakeVoiceService()),
        micSourceProvider.overrideWithValue(FakeMicSource()),
        audioSinkProvider.overrideWithValue(FakeAudioSink()),
      ],
    );
    addTearDown(emptyContainer.dispose);
    emptyContainer.listen(handsFreeControllerProvider, (_, _) {});

    await emptyContainer
        .read(handsFreeControllerProvider.notifier)
        .start(onUserUtterance: (t) async => 'x');

    expect(
      emptyContainer.read(handsFreeControllerProvider).phase,
      HandsFreePhase.noModel,
    );
  });

  test(
    'full turn: Listening -> Thinking -> Speaking -> back to Listening',
    () async {
      final notifier = container.read(handsFreeControllerProvider.notifier);
      final heard = <String>[];
      await notifier.start(
        onUserUtterance: (text) async {
          heard.add(text);
          return 'sure, done';
        },
      );
      expect(
        container.read(handsFreeControllerProvider).phase,
        HandsFreePhase.listening,
      );

      mic.pushSpeech();
      mic.pushSilence();
      await pump();

      expect(heard, ['turn on the lights']);
      final speaking = container.read(handsFreeControllerProvider);
      expect(speaking.phase, HandsFreePhase.speaking);
      expect(speaking.lastAssistantText, 'sure, done');
      expect(sink.playCount, 1);

      // TTS finishes on its own -> back to Listening for the next turn.
      sink.completeNow();
      await pump();
      expect(
        container.read(handsFreeControllerProvider).phase,
        HandsFreePhase.listening,
      );
    },
  );

  test('G3: SpeechStarted during Speaking stops TTS and returns to Listening '
      '(barge-in)', () async {
    final notifier = container.read(handsFreeControllerProvider.notifier);
    await notifier.start(onUserUtterance: (text) async => 'reply');

    mic.pushSpeech();
    mic.pushSilence();
    await pump();
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.speaking,
    );
    expect(sink.playCount, 1);
    expect(sink.stopCount, 0);
    expect(voice.cancelCount, 0);

    // Barge-in: the user starts talking again while the reply is playing.
    mic.pushSpeech();
    await pump();

    final afterBargeIn = container.read(handsFreeControllerProvider);
    expect(
      afterBargeIn.phase,
      HandsFreePhase.listening,
      reason:
          'SpeechStarted during Speaking must cut straight back to '
          'Listening, not wait for the reply to finish',
    );
    expect(sink.stopCount, 1, reason: 'TTS playback must be cut');
    expect(
      voice.cancelCount,
      1,
      reason: 'in-flight synth/transcribe must be cancelled',
    );

    // The interrupting utterance itself becomes the next turn once it
    // closes — not dropped.
    mic.pushSilence();
    await pump();
    final afterInterruptingTurn = container.read(handsFreeControllerProvider);
    expect(afterInterruptingTurn.lastUserText, 'turn on the lights');
    expect(
      sink.playCount,
      2,
      reason: 'the barged-in utterance produced its own new reply',
    );
  });

  test('engine failure (null reply) returns to Listening with an error, not '
      'stuck in Thinking', () async {
    final notifier = container.read(handsFreeControllerProvider.notifier);
    await notifier.start(onUserUtterance: (text) async => null);

    mic.pushSpeech();
    mic.pushSilence();
    await pump();

    final state = container.read(handsFreeControllerProvider);
    expect(state.phase, HandsFreePhase.listening);
    expect(state.errorMessage, isNotNull);
    expect(sink.playCount, 0);
  });

  test('stop() tears the session down cleanly', () async {
    final notifier = container.read(handsFreeControllerProvider.notifier);
    await notifier.start(onUserUtterance: (text) async => 'ok');
    expect(mic.startCount, 1);

    await notifier.stop();

    expect(mic.stopCount, 1);
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.idle,
    );

    // Speech after stop() has no listener anymore — nothing to assert on a
    // closed stream beyond "it doesn't throw".
    mic.pushSpeech();
    await pump();
  });
}
