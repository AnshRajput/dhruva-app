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

  test('release before any speech -> empty transcript, no crash', () async {
    installAllVoiceModels(tmp);
    final notifier = container.read(voiceInputControllerProvider.notifier);
    await notifier.startHold();

    // Release immediately — no audio pushed at all.
    final finalText = await notifier.endHold();

    expect(finalText, isEmpty);
    expect(mic.stopCount, 1);
    expect(
      container.read(voiceInputControllerProvider).phase,
      VoiceInputPhase.idle,
    );
  });

  test('very long hold: many segments accumulate into liveText without '
      'truncation or crash', () async {
    installAllVoiceModels(tmp);
    final notifier = container.read(voiceInputControllerProvider.notifier);
    await notifier.startHold();

    for (var i = 0; i < 25; i++) {
      mic.pushSpeech();
      mic.pushSilence();
      await pump(10);
    }
    await pump();

    final finalText = await notifier.endHold();
    final expected = List.filled(25, 'hello world').join(' ');
    expect(finalText, expected);
    expect(
      container.read(voiceInputControllerProvider).phase,
      VoiceInputPhase.idle,
    );
  });

  test(
    'BUG (QA loop 6, severity: high — privacy/resource leak): disposing '
    'the controller mid-hold (e.g. the composer is navigated away from '
    'while the mic button is still pressed — `voiceInputControllerProvider` '
    'is `.autoDispose`, so this happens on ordinary back-navigation, not '
    'just a crash) never stops the mic. `VoiceInputController.build()`\'s '
    '`ref.onDispose` (voice_input_controller.dart) only cancels `_sub` '
    '(the transcribeStream subscription) — unlike '
    '`HandsFreeController.build()`, which keeps `_activeMic` and calls '
    '`_activeMic?.stop()` on dispose, this controller keeps no such '
    'reference and never calls `MicSource.stop()` except from `endHold()`. '
    'Cancelling the downstream subscription does not stop the upstream '
    '`record` package capture (a real OS mic session) — only `stop()` '
    'does that. Net effect: navigating away while holding the mic button '
    'leaves the microphone recording indefinitely with no UI affordance '
    'left to stop it. This test currently FAILS (red) — that IS the filed '
    'bug; fix by mirroring HandsFreeController\'s `_activeMic` pattern.',
    () async {
      installAllVoiceModels(tmp);
      final notifier = container.read(voiceInputControllerProvider.notifier);
      await notifier.startHold();
      expect(mic.startCount, 1);
      mic.pushSpeech(); // mid-utterance, nowhere near endHold()

      // Simulate the widget (and its `ref.watch`) disappearing — the
      // autoDispose provider is torn down with no explicit endHold().
      container.dispose();
      await pump();

      expect(
        mic.stopCount,
        1,
        reason:
            'the mic must be stopped on teardown, not just the Dart-side '
            'stream subscription',
      );
    },
  );

  test(
    'RACE (reviewer, Loop 6, privacy — same class as BUG-2): a release '
    'that lands before `startHold` finishes its opening awaits '
    '(`voiceModelInstallerProvider.future`, `loadVad`/`loadAsr`, '
    '`mic.start()` — all run before `phase` is ever set to `listening`) '
    'must not leave the mic capturing with nobody holding the button. '
    'Every other test in this file awaits `startHold()` before calling '
    '`endHold()`, which hid this: a fast tap-tap has `endHold()` run while '
    '`phase` is still `idle`, early-return as a no-op, and then '
    '`startHold()` opens the mic and enters `listening` regardless.',
    () async {
      installAllVoiceModels(tmp);
      final notifier = container.read(voiceInputControllerProvider.notifier);

      // Not awaited — simulates the fast tap-tap: release fires while
      // startHold's opening awaits are still in flight.
      final startFuture = notifier.startHold();
      final finalText = await notifier.endHold();
      await startFuture; // let startHold's suspended awaits resume/finish.

      expect(finalText, isEmpty);
      expect(
        mic.stopCount,
        1,
        reason: 'the mic startHold opened must be torn back down',
      );
      expect(
        container.read(voiceInputControllerProvider).phase,
        VoiceInputPhase.idle,
        reason: 'must not be left listening with nobody holding the button',
      );
    },
  );
}
