import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/features/voice/state/voice_playback_controller.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../voice_test_helpers.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;
  late FakeVoiceService voice;
  late FakeAudioSink sink;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('voice_playback_test_');
    voice = FakeVoiceService();
    sink = FakeAudioSink();
    container = ProviderContainer(
      overrides: [
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
        ),
        voiceServiceProvider.overrideWithValue(voice),
        audioSinkProvider.overrideWithValue(sink),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('no TTS voice installed -> error, nothing synthesized', () async {
    final notifier = container.read(voicePlaybackControllerProvider.notifier);
    await notifier.toggle(1, 'hello there');
    await pump();

    expect(voice.synthesizeCount, 0);
    expect(sink.playCount, 0);
    final state = container.read(voicePlaybackControllerProvider);
    expect(state.lastErrorMessageId, 1);
    expect(state.lastErrorMessageForId, isNotNull);
  });

  test('tap synthesizes + plays; state reports playing', () async {
    installAllVoiceModels(tmp);
    final notifier = container.read(voicePlaybackControllerProvider.notifier);

    await notifier.toggle(1, 'hello there');
    await pump();

    expect(voice.synthesizeCount, 1);
    expect(voice.lastSynthesizedText, 'hello there');
    expect(sink.playCount, 1);
    final state = container.read(voicePlaybackControllerProvider);
    expect(state.isPlaying(1), isTrue);
  });

  test('tapping the same message again stops playback', () async {
    installAllVoiceModels(tmp);
    final notifier = container.read(voicePlaybackControllerProvider.notifier);
    await notifier.toggle(1, 'hello there');
    await pump();
    expect(
      container.read(voicePlaybackControllerProvider).isPlaying(1),
      isTrue,
    );

    await notifier.toggle(1, 'hello there');

    expect(sink.stopCount, 1);
    final state = container.read(voicePlaybackControllerProvider);
    expect(state.isPlaying(1), isFalse);
    expect(state.activeMessageId, isNull);
  });

  test('playback finishing naturally resets to idle', () async {
    installAllVoiceModels(tmp);
    final notifier = container.read(voicePlaybackControllerProvider.notifier);
    await notifier.toggle(1, 'hello there');
    await pump();

    sink.completeNow();
    await pump();

    final state = container.read(voicePlaybackControllerProvider);
    expect(state.activeMessageId, isNull);
  });

  test('playing a second message stops the first', () async {
    installAllVoiceModels(tmp);
    final notifier = container.read(voicePlaybackControllerProvider.notifier);
    await notifier.toggle(1, 'first message');
    await pump();

    await notifier.toggle(2, 'second message');
    await pump();

    expect(sink.stopCount, greaterThanOrEqualTo(1));
    final state = container.read(voicePlaybackControllerProvider);
    expect(state.isPlaying(2), isTrue);
    expect(state.isPlaying(1), isFalse);
  });
}
