/// Hold-to-talk (Loop 6, T2, D1): press-and-hold mic capture -> VAD-segmented
/// transcription -> release finalizes into the composer's text field for the
/// user to edit before sending (chat-spec.md's "editable is safer" call,
/// per the Loop-6 build brief — never auto-send).
///
/// Whisper (the only ASR in the catalog, see `voice_model_catalog.dart`) is
/// non-streaming, so there's no true word-by-word partial — [VoiceInputState
/// .liveText] instead grows one closed VAD segment at a time while the
/// button is held (`VoiceService.transcribeStream` already does the
/// segment-then-transcribe work; see its doc comment), which is what the
/// composer shows as the "live" transcript. `MicSource`/`VoiceService` are
/// both DI seams (`FakeMicSource`/`FakeVoiceService`), so this whole flow is
/// unit-testable without a real mic or native libs.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../voice/mic_audio_source.dart' show MicSource;
import '../../../voice/voice_model_catalog.dart';
import '../../../voice/voice_service.dart';

enum VoiceInputPhase {
  idle,

  /// Mic open, VAD+ASR running; [VoiceInputState.liveText] grows as
  /// segments close.
  listening,

  /// `MicSource.start()` threw because the OS denied mic access.
  permissionDenied,

  /// VAD and/or ASR isn't installed — chat-spec.md §7.1's "no model
  /// installed" pattern, voice's version.
  noModel,
}

final class VoiceInputState {
  final VoiceInputPhase phase;
  final String liveText;

  const VoiceInputState({
    this.phase = VoiceInputPhase.idle,
    this.liveText = '',
  });

  VoiceInputState copyWith({VoiceInputPhase? phase, String? liveText}) =>
      VoiceInputState(
        phase: phase ?? this.phase,
        liveText: liveText ?? this.liveText,
      );
}

final voiceInputControllerProvider =
    NotifierProvider.autoDispose<VoiceInputController, VoiceInputState>(
      VoiceInputController.new,
    );

class VoiceInputController extends Notifier<VoiceInputState> {
  StreamSubscription<Transcript>? _sub;
  Completer<void>? _streamDone;

  /// Captured in [startHold] so [build]'s `ref.onDispose` can release the
  /// mic without touching `ref` (not allowed inside a dispose callback —
  /// same reasoning as `HandsFreeController._activeMic`). QA BUG-2: without
  /// this, disposing mid-hold (e.g. back-navigation while the mic button is
  /// still pressed — this provider is `.autoDispose`) only cancelled the
  /// downstream `transcribeStream` subscription; the upstream `record`
  /// capture — a real OS mic session — kept running with no UI left to stop
  /// it.
  MicSource? _activeMic;

  /// Reviewer-filed race (same class as QA BUG-2): [startHold] awaits
  /// `voiceModelInstallerProvider.future`, `loadVad`/`loadAsr`, and
  /// `mic.start()` — all before it ever sets `phase = listening`. On a fast
  /// tap, [endHold] can run and early-return (`state.phase !=
  /// VoiceInputPhase.listening`) WHILE those awaits are still in flight —
  /// then `startHold` finishes, opens the mic, and enters `listening` with
  /// no one left holding the button: the mic captures indefinitely until a
  /// second, unrelated tap. Set the instant [endHold] is called, checked by
  /// [startHold] right after `mic.start()` (the earliest point a real mic
  /// session exists) so a release-during-startup tears the just-opened mic
  /// back down instead of entering `listening`.
  bool _releaseRequested = false;

  @override
  VoiceInputState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      unawaited(_activeMic?.stop());
    });
    return const VoiceInputState();
  }

  /// Called on press-down. No-op if already listening.
  Future<void> startHold() async {
    if (state.phase == VoiceInputPhase.listening) return;
    _releaseRequested = false;

    final installer = await ref.read(voiceModelInstallerProvider.future);
    final asrEntry = voiceModelCatalog.firstWhere(
      (e) => e.role == VoiceModelRole.asr,
    );
    if (!installer.isInstalled(vadCatalogEntry) ||
        !installer.isInstalled(asrEntry)) {
      state = state.copyWith(phase: VoiceInputPhase.noModel);
      return;
    }

    final voice = ref.read(voiceServiceProvider);
    try {
      if (!voice.isVadReady) {
        await voice.loadVad(installer.vadConfig(vadCatalogEntry));
      }
      if (!voice.isAsrReady) {
        await voice.loadAsr(installer.asrConfig(asrEntry));
      }
    } on VoiceFailure {
      state = state.copyWith(phase: VoiceInputPhase.noModel);
      return;
    }

    final mic = ref.read(micSourceProvider);
    final Stream<Float32List> audio;
    try {
      audio = await mic.start();
    } on VoiceValidationFailure {
      state = state.copyWith(phase: VoiceInputPhase.permissionDenied);
      return;
    }
    _activeMic = mic;

    // The race: `endHold` already ran (and no-opped) while the awaits above
    // were in flight — don't enter `listening` with nobody holding the
    // button, tear the mic we just opened back down instead.
    if (_releaseRequested) {
      _activeMic = null;
      _releaseRequested = false;
      await mic.stop();
      return;
    }

    state = VoiceInputState(phase: VoiceInputPhase.listening, liveText: '');
    final done = Completer<void>();
    _streamDone = done;
    _sub = voice
        .transcribeStream(audio)
        .listen(
          (t) {
            if (t.text.trim().isEmpty) return;
            final joined = state.liveText.isEmpty
                ? t.text
                : '${state.liveText} ${t.text}';
            state = state.copyWith(liveText: joined);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          onError: (Object _) {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
  }

  /// Called on release. Stops the mic, waits for the last in-flight segment
  /// to finish transcribing (whisper decode of a short clip is ~1s, per the
  /// T1 handoff — bounded here so a stuck decode can't hang the composer
  /// forever), and returns the finalized text for the caller to drop into
  /// the composer's `TextEditingController`. Resets to idle either way.
  Future<String> endHold() async {
    _releaseRequested = true;
    if (state.phase != VoiceInputPhase.listening) {
      // Belt-and-suspenders: `startHold` may have already opened a real mic
      // session (captured into `_activeMic`) without having reached
      // `listening` yet — stop it regardless of phase rather than trusting
      // `_releaseRequested` alone to be checked in time.
      final mic = _activeMic;
      _activeMic = null;
      await mic?.stop();
      return '';
    }
    final mic = ref.read(micSourceProvider);
    await mic.stop();
    _activeMic = null;
    final done = _streamDone;
    if (done != null) {
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    // Not awaited: `onDone` already fired by this point (that's what `done`
    // resolving means), so the subscription has already run to completion —
    // `.cancel()` here is just releasing the `StreamSubscription` object,
    // and (same lesson as `HandsFreeController.stop`) awaiting a cancel on
    // an async*-derived stream can leave the Future pending well past the
    // point its own work is actually done.
    unawaited(_sub?.cancel());
    _sub = null;
    _streamDone = null;
    final text = state.liveText;
    state = const VoiceInputState();
    return text;
  }
}
