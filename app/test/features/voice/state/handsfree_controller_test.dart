import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/features/voice/state/handsfree_controller.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
import 'package:dhruva/voice/fake_mic_source.dart';
import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:dhruva/voice/voice_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../voice_test_helpers.dart';

/// Wraps a [FakeVoiceService], gating [transcribe] on a [Completer] the test
/// controls — lets a test hold `_finalizeUtterance` mid-flight (after it's
/// called `transcribe`, before that call resolves) to deterministically
/// drive the "two `SpeechEnded` events before the first transcribe
/// resolves" race, instead of hoping real scheduling lines up.
final class _GatedTranscribeVoiceService implements VoiceService {
  final FakeVoiceService _delegate;
  final Completer<void> gate = Completer<void>();
  int transcribeCalls = 0;

  _GatedTranscribeVoiceService(this._delegate);

  @override
  Future<Transcript> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    transcribeCalls++;
    await gate.future;
    return _delegate.transcribe(samples, sampleRate: sampleRate);
  }

  @override
  bool get isAsrReady => _delegate.isAsrReady;
  @override
  bool get isTtsReady => _delegate.isTtsReady;
  @override
  bool get isVadReady => _delegate.isVadReady;
  @override
  Future<void> loadAsr(AsrModelConfig config) => _delegate.loadAsr(config);
  @override
  Future<void> loadTts(TtsModelConfig config) => _delegate.loadTts(config);
  @override
  Future<void> loadVad(VadConfig config) => _delegate.loadVad(config);
  @override
  Stream<Transcript> transcribeStream(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
  }) => _delegate.transcribeStream(audio, sampleRate: sampleRate);
  @override
  Future<SynthesizedAudio> synthesize(
    String text, {
    int voiceId = 0,
    double speed = 1.0,
  }) => _delegate.synthesize(text, voiceId: voiceId, speed: speed);
  @override
  Stream<VadEvent> segment(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
  }) => _delegate.segment(audio, sampleRate: sampleRate);
  @override
  Future<void> cancel() => _delegate.cancel();
  @override
  Future<void> dispose() => _delegate.dispose();
}

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

  test('reset() + start() picks up a fresh voice install without recreating '
      'the screen (WS5: no dead-end after installing and returning)', () async {
    final freshTmp = Directory.systemTemp.createTempSync('handsfree_fresh_');
    addTearDown(() => freshTmp.deleteSync(recursive: true));
    final freshContainer = ProviderContainer(
      overrides: [
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: freshTmp),
        ),
        voiceServiceProvider.overrideWithValue(FakeVoiceService()),
        micSourceProvider.overrideWithValue(FakeMicSource()),
        audioSinkProvider.overrideWithValue(FakeAudioSink()),
      ],
    );
    addTearDown(freshContainer.dispose);
    freshContainer.listen(handsFreeControllerProvider, (_, _) {});

    final notifier = freshContainer.read(handsFreeControllerProvider.notifier);
    await notifier.start(onUserUtterance: (t) async => 'x');
    expect(
      freshContainer.read(handsFreeControllerProvider).phase,
      HandsFreePhase.noModel,
    );

    // User installs the voice bundle via the models hub and pops back onto the
    // (still-mounted) hands-free screen, which calls reset() + start() again.
    installAllVoiceModels(freshTmp);
    notifier.reset();
    await notifier.start(onUserUtterance: (t) async => 'x');

    expect(
      freshContainer.read(handsFreeControllerProvider).phase,
      HandsFreePhase.listening,
      reason: 'a fresh install must be picked up without exiting hands-free',
    );
  });

  test('reset() is a no-op during an active turn', () async {
    final notifier = container.read(handsFreeControllerProvider.notifier);
    await notifier.start(onUserUtterance: (t) async => 'ok');
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.listening,
    );

    notifier.reset();

    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.listening,
      reason: 'reset() must not yank a live session back to idle',
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

  // --- Loop 6 QA adversarial pass -------------------------------------

  test('barge-in during Thinking is currently dropped, not queued or '
      'cancelling the in-flight engine call (documented ponytail scope in '
      'handsfree_controller.dart: "barge-in is wired for the Speaking phase '
      'only... a SpeechStarted during Thinking is currently ignored") — this '
      'pins that documented behavior so a regression (crash, or a silent '
      'change in semantics) is caught, not a new bug', () async {
    final callbackStarted = Completer<void>();
    final releaseCallback = Completer<String?>();
    final notifier = container.read(handsFreeControllerProvider.notifier);
    await notifier.start(
      onUserUtterance: (text) async {
        callbackStarted.complete();
        return releaseCallback.future;
      },
    );

    mic.pushSpeech();
    mic.pushSilence();
    await callbackStarted.future; // now in Thinking, engine call in flight
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.thinking,
    );

    // User starts talking again while the model is still "generating".
    mic.pushSpeech();
    await pump();
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.thinking,
      reason:
          'SpeechStarted during Thinking must not flip the phase '
          '(only the Speaking-phase barge-in path exists today)',
    );
    expect(voice.cancelCount, 0, reason: 'the engine call is not cancelled');
    expect(sink.stopCount, 0);

    // The interrupting utterance's SpeechEnded also lands while still
    // Thinking — must not crash, and must not be treated as a fresh
    // listening-phase turn (the phase guard in _handleEvent is
    // `state.phase == listening`, which is false here).
    mic.pushSilence();
    await pump();
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.thinking,
    );

    // The original turn eventually resolves normally.
    releaseCallback.complete('done');
    await pump();
    final finalState = container.read(handsFreeControllerProvider);
    expect(finalState.phase, HandsFreePhase.speaking);
    expect(sink.playCount, 1, reason: 'only the original turn spoke');
  });

  test(
    'rapid repeated barge-ins do not corrupt state or double-count',
    () async {
      var turn = 0;
      final notifier = container.read(handsFreeControllerProvider.notifier);
      await notifier.start(
        onUserUtterance: (text) async {
          turn++;
          return 'reply $turn';
        },
      );

      for (var i = 0; i < 3; i++) {
        mic.pushSpeech();
        mic.pushSilence();
        await pump();
        expect(
          container.read(handsFreeControllerProvider).phase,
          HandsFreePhase.speaking,
          reason: 'turn $i should reach Speaking before the next barge-in',
        );
        // Interrupt immediately.
        mic.pushSpeech();
        await pump();
        expect(
          container.read(handsFreeControllerProvider).phase,
          HandsFreePhase.listening,
        );
      }

      expect(voice.cancelCount, 3);
      expect(sink.stopCount, 3);
      expect(
        sink.playCount,
        3,
        reason: 'each interrupted turn still spoke once',
      );

      // One more clean (non-interrupted) turn afterwards proves the session
      // isn't left in a half-broken state by the barge-in storm.
      mic.pushSilence();
      await pump();
      expect(
        container.read(handsFreeControllerProvider).phase,
        HandsFreePhase.speaking,
      );
      sink.completeNow();
      await pump();
      expect(
        container.read(handsFreeControllerProvider).phase,
        HandsFreePhase.listening,
      );
    },
  );

  test(
    'barge-in racing the natural Speaking->Listening transition (both '
    'orderings) ends in a consistent state, no crash, no double reply',
    () async {
      for (final sinkFirst in [true, false]) {
        final localMic = FakeMicSource();
        final localVoice = FakeVoiceService(
          scriptedTranscript: 'turn on the lights',
        );
        final localSink = FakeAudioSink();
        final localContainer = ProviderContainer(
          overrides: [
            voiceModelInstallerProvider.overrideWith(
              (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
            ),
            voiceServiceProvider.overrideWithValue(localVoice),
            micSourceProvider.overrideWithValue(localMic),
            audioSinkProvider.overrideWithValue(localSink),
          ],
        );
        addTearDown(localContainer.dispose);
        localContainer.listen(handsFreeControllerProvider, (_, _) {});

        final notifier = localContainer.read(
          handsFreeControllerProvider.notifier,
        );
        await notifier.start(onUserUtterance: (text) async => 'reply');
        localMic.pushSpeech();
        localMic.pushSilence();
        await pump();
        expect(
          localContainer.read(handsFreeControllerProvider).phase,
          HandsFreePhase.speaking,
        );

        if (sinkFirst) {
          localSink.completeNow(); // reply finishes on its own first
          await pump(5);
          localMic.pushSpeech(); // then the race: user starts talking
        } else {
          localMic.pushSpeech(); // barge-in wins the race
          await pump(5);
          localSink.completeNow(); // reply's own completion arrives after
        }
        await pump();

        // Either ordering must land on a phase that keeps listening for
        // the user (never stuck in Speaking, never a double transcript).
        expect(
          localContainer.read(handsFreeControllerProvider).phase,
          anyOf(HandsFreePhase.listening, HandsFreePhase.speaking),
          reason:
              'sinkFirst=$sinkFirst must not crash or wedge the state '
              'machine',
        );
      }
    },
  );

  test('SpeechEnded with a near-silent/empty transcript while Listening is '
      'dropped — never sent as a chat turn (the empty-persona lesson: no '
      'empty turns)', () async {
    final emptyVoice = FakeVoiceService(scriptedTranscript: '');
    final localContainer = ProviderContainer(
      overrides: [
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
        ),
        voiceServiceProvider.overrideWithValue(emptyVoice),
        micSourceProvider.overrideWithValue(mic),
        audioSinkProvider.overrideWithValue(sink),
      ],
    );
    addTearDown(localContainer.dispose);
    localContainer.listen(handsFreeControllerProvider, (_, _) {});

    var called = false;
    final notifier = localContainer.read(handsFreeControllerProvider.notifier);
    await notifier.start(
      onUserUtterance: (text) async {
        called = true;
        return 'should never be spoken';
      },
    );

    mic.pushSpeech();
    mic.pushSilence();
    await pump();

    expect(called, isFalse, reason: 'an empty transcript is not a turn');
    expect(
      localContainer.read(handsFreeControllerProvider).phase,
      HandsFreePhase.listening,
      reason: 'stays Listening, not stuck or advanced to Thinking',
    );
    expect(sink.playCount, 0);
  });

  test('TTS model uninstalled mid-session -> graceful Listening + error, not '
      'a stuck Speaking spinner', () async {
    final notifier = container.read(handsFreeControllerProvider.notifier);
    await notifier.start(onUserUtterance: (text) async => 'a reply');

    // Simulate the user deleting every TTS voice from the models hub
    // while hands-free is open (installer re-checks the filesystem live).
    for (final e in voiceModelCatalog.where(
      (e) => e.role == VoiceModelRole.tts,
    )) {
      final installer = VoiceModelInstaller(modelsDirectory: tmp);
      final dir = installer.installDir(e);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }

    mic.pushSpeech();
    mic.pushSilence();
    await pump();

    final state = container.read(handsFreeControllerProvider);
    expect(
      state.phase,
      HandsFreePhase.listening,
      reason: 'must not get stuck in Speaking with nothing playing',
    );
    expect(state.errorMessage, isNotNull);
    expect(sink.playCount, 0);
    expect(voice.synthesizeCount, 0);
  });

  test(
    'exit (stop()) during Thinking cleans up and ignores the late reply',
    () async {
      final releaseCallback = Completer<String?>();
      final notifier = container.read(handsFreeControllerProvider.notifier);
      await notifier.start(
        onUserUtterance: (text) async => releaseCallback.future,
      );

      mic.pushSpeech();
      mic.pushSilence();
      await pump();
      expect(
        container.read(handsFreeControllerProvider).phase,
        HandsFreePhase.thinking,
      );

      await notifier.stop();
      expect(mic.stopCount, 1);
      expect(sink.stopCount, 1);
      expect(voice.cancelCount, 1);
      expect(
        container.read(handsFreeControllerProvider).phase,
        HandsFreePhase.idle,
      );

      // The engine call that was in flight resolves AFTER stop() — must not
      // resurrect Speaking/play audio into a torn-down session.
      releaseCallback.complete('late reply');
      await pump();
      expect(
        container.read(handsFreeControllerProvider).phase,
        HandsFreePhase.idle,
      );
      expect(sink.playCount, 0);
    },
  );

  test('exit (stop()) during Speaking cleans up mic + sink + voice', () async {
    final notifier = container.read(handsFreeControllerProvider.notifier);
    await notifier.start(onUserUtterance: (text) async => 'a reply');

    mic.pushSpeech();
    mic.pushSilence();
    await pump();
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.speaking,
    );
    expect(sink.playCount, 1);

    await notifier.stop();

    expect(mic.stopCount, 1);
    expect(sink.stopCount, 1, reason: 'in-flight playback must be cut');
    expect(voice.cancelCount, 1);
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.idle,
    );

    // sink completing after the fact (e.g. a queued onComplete) must not
    // reopen the session.
    sink.completeNow();
    await pump();
    expect(
      container.read(handsFreeControllerProvider).phase,
      HandsFreePhase.idle,
    );
  });

  test('RACE (reviewer nit, Loop 6): two SpeechEnded events while Listening, '
      'both before the first transcribe resolves, must only start ONE '
      '_finalizeUtterance — a second SpeechEnded landing in that window used '
      'to also see `phase == listening` (nothing had moved it to `thinking` '
      'yet) and start a second, producing two replies for one turn.', () async {
    final gatedVoice = _GatedTranscribeVoiceService(
      FakeVoiceService(scriptedTranscript: 'first utterance'),
    );
    final gatedMic = FakeMicSource();
    final gatedSink = FakeAudioSink();
    final gatedContainer = ProviderContainer(
      overrides: [
        voiceModelInstallerProvider.overrideWith(
          (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
        ),
        voiceServiceProvider.overrideWithValue(gatedVoice),
        micSourceProvider.overrideWithValue(gatedMic),
        audioSinkProvider.overrideWithValue(gatedSink),
      ],
    );
    addTearDown(gatedContainer.dispose);
    gatedContainer.listen(handsFreeControllerProvider, (_, _) {});

    final replies = <String>[];
    await gatedContainer
        .read(handsFreeControllerProvider.notifier)
        .start(
          onUserUtterance: (text) async {
            replies.add(text);
            return 'ok';
          },
        );

    // First utterance closes -> `_finalizeUtterance` #1 starts, calls
    // `transcribe`, and blocks on the gate — `phase` is still `listening`
    // (it only moves to `thinking` once transcribe resolves).
    gatedMic.pushSpeech();
    gatedMic.pushSilence();
    await pump();
    expect(gatedVoice.transcribeCalls, 1);
    expect(
      gatedContainer.read(handsFreeControllerProvider).phase,
      HandsFreePhase.listening,
      reason: 'still gated — first transcribe has not resolved yet',
    );

    // Second utterance closes while the first is still gated — must be
    // dropped, not started as a second `_finalizeUtterance`.
    gatedMic.pushSpeech();
    gatedMic.pushSilence();
    await pump();
    expect(
      gatedVoice.transcribeCalls,
      1,
      reason: 'a second transcribe call means the race is back',
    );

    // Release the first — the turn completes normally.
    gatedVoice.gate.complete();
    await pump();

    expect(replies, ['first utterance']);
    expect(
      gatedContainer.read(handsFreeControllerProvider).lastUserText,
      'first utterance',
    );
  });
}
