/// Per-message TTS playback (Loop 6, T2, D2): the speaker button on an
/// assistant bubble synthesizes + plays through the shared [AudioSink]
/// (`voice/voice_player.dart`); tapping the currently-playing message's
/// button again stops it. Only one message plays at a time — a second tap
/// elsewhere stops whatever was playing first (same "stops anything already
/// playing" contract `AudioSink.play` already has).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../voice/voice_service.dart';
import 'default_voice.dart';

enum VoicePlaybackPhase { idle, synthesizing, playing }

final class VoicePlaybackState {
  final int? activeMessageId;
  final VoicePlaybackPhase phase;

  /// Set (and only meaningful) right after a failed [VoicePlaybackController
  /// .toggle] call, for a one-shot snackbar/toast — cleared on the next
  /// state change.
  final String? lastErrorMessageForId;
  final int? lastErrorMessageId;

  const VoicePlaybackState({
    this.activeMessageId,
    this.phase = VoicePlaybackPhase.idle,
    this.lastErrorMessageForId,
    this.lastErrorMessageId,
  });

  bool isPlaying(int messageId) =>
      activeMessageId == messageId && phase == VoicePlaybackPhase.playing;
  bool isSynthesizing(int messageId) =>
      activeMessageId == messageId && phase == VoicePlaybackPhase.synthesizing;
}

final voicePlaybackControllerProvider =
    NotifierProvider<VoicePlaybackController, VoicePlaybackState>(
      VoicePlaybackController.new,
    );

class VoicePlaybackController extends Notifier<VoicePlaybackState> {
  StreamSubscription<void>? _completeSub;
  String? _loadedVoiceEntryId;

  @override
  VoicePlaybackState build() {
    final sink = ref.watch(audioSinkProvider);
    _completeSub?.cancel();
    _completeSub = sink.onComplete.listen((_) {
      state = const VoicePlaybackState();
    });
    ref.onDispose(() => unawaited(_completeSub?.cancel()));
    return const VoicePlaybackState();
  }

  /// Speaker button tap: starts speaking [text] for [messageId], or — if
  /// [messageId] is already playing/synthesizing — stops it.
  Future<void> toggle(int messageId, String text) async {
    final sink = ref.read(audioSinkProvider);
    if (state.activeMessageId == messageId) {
      await sink.stop();
      state = const VoicePlaybackState();
      return;
    }
    if (state.activeMessageId != null) {
      await sink.stop(); // a different message was playing; cut it first.
    }

    final entry = defaultVoiceEntryFor(text);
    final installer = await ref.read(voiceModelInstallerProvider.future);
    if (entry == null || !installer.isInstalled(entry)) {
      state = VoicePlaybackState(
        lastErrorMessageId: messageId,
        lastErrorMessageForId: 'no TTS voice installed',
      );
      return;
    }

    state = VoicePlaybackState(
      activeMessageId: messageId,
      phase: VoicePlaybackPhase.synthesizing,
    );
    final voice = ref.read(voiceServiceProvider);
    try {
      if (!voice.isTtsReady || _loadedVoiceEntryId != entry.id) {
        await voice.loadTts(installer.ttsConfig(entry));
        _loadedVoiceEntryId = entry.id;
      }
      final audio = await voice.synthesize(text);
      if (state.activeMessageId != messageId) return; // stopped mid-synth
      await sink.play(audio);
      state = VoicePlaybackState(
        activeMessageId: messageId,
        phase: VoicePlaybackPhase.playing,
      );
    } on VoiceFailure catch (e) {
      state = VoicePlaybackState(
        lastErrorMessageId: messageId,
        lastErrorMessageForId: e.message,
      );
    }
  }

  Future<void> stop() async {
    await ref.read(audioSinkProvider).stop();
    state = const VoicePlaybackState();
  }
}
