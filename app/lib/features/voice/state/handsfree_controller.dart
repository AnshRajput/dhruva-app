/// Hands-free conversation mode (Loop 6, T2/T3, D3 — "the signature
/// orchestration feature", G3 exit gate).
///
/// State machine: Listening -> Thinking -> Speaking -> Listening, driven by
/// ONE continuous [VoiceService.segment] subscription opened in [start] and
/// held open for the whole session (mirrors the T1 HANDOFF's own barge-in
/// design note: "hands-free loop listens for SpeechStarted during TTS
/// playback; caller stops the player + calls `voice.cancel()`" — a single
/// long-lived listener, not a cancel/resubscribe dance per turn).
///
/// BARGE-IN (G3): a [SpeechStarted] event that arrives while [HandsFreePhase
/// .speaking] stops the [AudioSink] immediately, calls [VoiceService.cancel]
/// (discards in-flight synth/transcribe per its contract), and flips the
/// phase straight to [HandsFreePhase.listening] — the SAME event's matching
/// [SpeechEnded], which arrives later, is then processed as an ordinary
/// listening-phase utterance (the phase check in [_handleEvent] falls
/// through to the normal path once the phase flip has happened), so the
/// words the user started speaking mid-reply become their next turn rather
/// than being dropped.
///
/// ponytail: barge-in is wired for the Speaking phase only (what the build
/// brief's G3 gate asks for) — a [SpeechStarted] during Thinking is
/// currently ignored (the engine call in flight isn't cancelled), so an
/// utterance spoken while the model is still generating is dropped rather
/// than interrupting generation. Add a `cancel` hook alongside
/// [HandsFreeController.start]'s `onUserUtterance` callback if Thinking-phase
/// interruption is wanted later — `ChatController.cancel()` already exists
/// on the chat side to hang it off of.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../voice/mic_audio_source.dart' show MicSource;
import '../../../voice/voice_model_catalog.dart';
import '../../../voice/voice_service.dart';
import 'default_voice.dart';

enum HandsFreePhase {
  /// Not started, or [HandsFreeController.stop] was called.
  idle,
  listening,
  thinking,
  speaking,

  /// VAD/ASR/TTS isn't all installed — hands-free needs every model
  /// (unlike hold-to-talk, which only needs VAD+ASR).
  noModel,
  permissionDenied,
}

final class HandsFreeState {
  final HandsFreePhase phase;
  final String? lastUserText;
  final String? lastAssistantText;
  final String? errorMessage;

  const HandsFreeState({
    this.phase = HandsFreePhase.idle,
    this.lastUserText,
    this.lastAssistantText,
    this.errorMessage,
  });

  HandsFreeState copyWith({
    HandsFreePhase? phase,
    String? lastUserText,
    String? lastAssistantText,
    String? errorMessage,
    bool clearError = false,
  }) => HandsFreeState(
    phase: phase ?? this.phase,
    lastUserText: lastUserText ?? this.lastUserText,
    lastAssistantText: lastAssistantText ?? this.lastAssistantText,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

final handsFreeControllerProvider =
    NotifierProvider.autoDispose<HandsFreeController, HandsFreeState>(
      HandsFreeController.new,
    );

class HandsFreeController extends Notifier<HandsFreeState> {
  StreamSubscription<VadEvent>? _vadSub;
  StreamSubscription<void>? _completeSub;
  Future<String?> Function(String userText)? _onUserUtterance;
  String? _loadedVoiceEntryId;

  /// Captured in [start] so [build]'s `ref.onDispose` can release the mic
  /// without touching `ref` itself — `Ref.read` isn't allowed inside a
  /// dispose callback (riverpod's `_debugCallbackStack` guard), only field
  /// access is.
  MicSource? _activeMic;

  /// Reviewer-filed race: [_finalizeUtterance] doesn't move `phase` off
  /// `listening` until AFTER its first `await` (`voice.transcribe`)
  /// resolves — a second [SpeechEnded] arriving while that's still in
  /// flight would see `phase == listening` too and start a SECOND
  /// `_finalizeUtterance`, producing two replies for what should be one
  /// turn. Set the instant one starts, cleared when it's done (whichever
  /// way it exits), and checked alongside the phase in [_handleEvent].
  bool _finalizing = false;

  @override
  HandsFreeState build() {
    ref.onDispose(() {
      unawaited(_vadSub?.cancel());
      unawaited(_completeSub?.cancel());
      unawaited(_activeMic?.stop());
    });
    return const HandsFreeState();
  }

  /// Starts the session: validates all three model roles are installed,
  /// opens the mic, and begins the Listening/Thinking/Speaking loop.
  /// [onUserUtterance] is called with each finalized user utterance and must
  /// return the assistant's reply text (or null on failure — the loop
  /// returns to Listening with [HandsFreeState.errorMessage] set rather than
  /// getting stuck). Owned by the screen so this controller never imports
  /// `features/chat` (ADR-002).
  Future<void> start({
    required Future<String?> Function(String userText) onUserUtterance,
  }) async {
    if (state.phase != HandsFreePhase.idle) return;
    _onUserUtterance = onUserUtterance;

    final installer = await ref.read(voiceModelInstallerProvider.future);
    final asrEntry = voiceModelCatalog.firstWhere(
      (e) => e.role == VoiceModelRole.asr,
    );
    final anyTtsInstalled = voiceModelCatalog
        .where((e) => e.role == VoiceModelRole.tts)
        .any(installer.isInstalled);
    if (!installer.isInstalled(vadCatalogEntry) ||
        !installer.isInstalled(asrEntry) ||
        !anyTtsInstalled) {
      state = state.copyWith(phase: HandsFreePhase.noModel);
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
      state = state.copyWith(phase: HandsFreePhase.noModel);
      return;
    }

    final mic = ref.read(micSourceProvider);
    _activeMic = mic;
    final Stream<Float32List> audio;
    try {
      audio = await mic.start();
    } on VoiceValidationFailure {
      state = state.copyWith(phase: HandsFreePhase.permissionDenied);
      return;
    }

    final sink = ref.read(audioSinkProvider);
    _completeSub = sink.onComplete.listen((_) {
      if (state.phase == HandsFreePhase.speaking) {
        state = state.copyWith(phase: HandsFreePhase.listening);
      }
    });

    state = const HandsFreeState(phase: HandsFreePhase.listening);
    _vadSub = voice.segment(audio).listen(_handleEvent);
  }

  /// Resets a non-running session back to `idle` so [start] (which early-
  /// returns unless `phase == idle`) can run again. Used by the screen's
  /// "try again" path after the user installs voice models and returns: the
  /// screen State isn't recreated (it sits under the pushed models route), so
  /// without this the phase would stay `noModel`/`permissionDenied` forever.
  /// A no-op while a turn is actually flowing, so it can't yank a live
  /// session out from under itself.
  void reset() {
    switch (state.phase) {
      case HandsFreePhase.listening:
      case HandsFreePhase.thinking:
      case HandsFreePhase.speaking:
        return;
      case HandsFreePhase.idle:
      case HandsFreePhase.noModel:
      case HandsFreePhase.permissionDenied:
        state = const HandsFreeState();
    }
  }

  Future<void> stop() async {
    // Fire-and-forget, not awaited: cancelling a subscription to a
    // `segment()` stream that's still mid-`await for` on a live (not yet
    // closed) mic stream can leave `.cancel()`'s Future pending until the
    // upstream is actually torn down — `mic.stop()` below is what actually
    // ends the audio stream, so waiting on the subscription cancel first
    // would risk this method hanging on exactly the "stop everything"
    // path that most needs to complete promptly (same reasoning as
    // `build()`'s `ref.onDispose` cleanup, which is fire-and-forget too).
    unawaited(_vadSub?.cancel());
    _vadSub = null;
    unawaited(_completeSub?.cancel());
    _completeSub = null;
    await ref.read(audioSinkProvider).stop();
    await ref.read(micSourceProvider).stop();
    await ref.read(voiceServiceProvider).cancel();
    state = const HandsFreeState();
  }

  void _handleEvent(VadEvent event) {
    switch (event) {
      case SpeechStarted():
        if (state.phase == HandsFreePhase.speaking) {
          // Barge-in (G3): cut the reply short and start listening for what
          // the user is saying right now.
          unawaited(ref.read(audioSinkProvider).stop());
          unawaited(ref.read(voiceServiceProvider).cancel());
          state = state.copyWith(phase: HandsFreePhase.listening);
        }
      case SpeechEnded(:final samples):
        if (state.phase == HandsFreePhase.listening && !_finalizing) {
          _finalizing = true;
          unawaited(_finalizeUtterance(samples));
        }
    }
  }

  Future<void> _finalizeUtterance(Float32List samples) async {
    try {
      final voice = ref.read(voiceServiceProvider);
      final Transcript transcript;
      try {
        transcript = await voice.transcribe(samples);
      } on VoiceFailure catch (e) {
        state = state.copyWith(errorMessage: e.message);
        return;
      }
      final text = transcript.text.trim();
      if (text.isEmpty) {
        return; // noise/silence VAD mis-segmented; stay listening
      }

      state = state.copyWith(
        phase: HandsFreePhase.thinking,
        lastUserText: text,
        clearError: true,
      );
      final callback = _onUserUtterance;
      final reply = callback == null ? null : await callback(text);
      // A barge-in (or `stop()`) may have already moved the phase on while
      // we were awaiting the engine — don't stomp back to speaking/
      // listening over whatever the user's interruption already decided.
      if (state.phase != HandsFreePhase.thinking) return;
      if (reply == null || reply.trim().isEmpty) {
        state = state.copyWith(
          phase: HandsFreePhase.listening,
          errorMessage: 'The model could not generate a reply.',
        );
        return;
      }
      state = state.copyWith(
        phase: HandsFreePhase.speaking,
        lastAssistantText: reply,
      );
      await _speak(reply);
    } finally {
      _finalizing = false;
    }
  }

  Future<void> _speak(String text) async {
    final installer = await ref.read(voiceModelInstallerProvider.future);
    // Prefer the language-matched voice, but fall back to any INSTALLED voice
    // so a Hindi reply still speaks in English (accented but audible) when
    // only the English bundle voice is on disk — the alternative is a silent,
    // text-only turn. `entry` is therefore guaranteed installed when non-null;
    // it's null only when no TTS voice exists at all, which the `start()` gate
    // (`anyTtsInstalled`) already rules out, so this is defensive.
    final entry = defaultVoiceEntryFor(
      text,
      isInstalled: installer.isInstalled,
    );
    if (entry == null) {
      state = state.copyWith(
        phase: HandsFreePhase.listening,
        errorMessage: 'No TTS voice installed — reply shown as text only.',
      );
      return;
    }
    final voice = ref.read(voiceServiceProvider);
    try {
      if (!voice.isTtsReady || _loadedVoiceEntryId != entry.id) {
        await voice.loadTts(installer.ttsConfig(entry));
        _loadedVoiceEntryId = entry.id;
      }
      final audio = await voice.synthesize(text);
      // Barge-in landed while we were synthesizing: don't start playback for
      // a reply the user has already talked over.
      if (state.phase != HandsFreePhase.speaking) return;
      await ref.read(audioSinkProvider).play(audio);
    } on VoiceFailure catch (e) {
      state = state.copyWith(
        phase: HandsFreePhase.listening,
        errorMessage: e.message,
      );
    }
  }
}
