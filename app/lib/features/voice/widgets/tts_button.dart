/// Speaker button on an assistant message bubble (Loop 6, T2, D2): tap to
/// synthesize + play, tap again to stop. Uses the conversation's character
/// voice if the catalog has a language match for the text, else the default
/// English voice — see `state/default_voice.dart`'s doc comment for the
/// `Character.voiceId` gap this loop ships without.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/voice_playback_controller.dart';

class TtsButton extends ConsumerWidget {
  final int messageId;
  final String text;

  const TtsButton({super.key, required this.messageId, required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(voicePlaybackControllerProvider, (previous, next) {
      if (next.lastErrorMessageId == messageId &&
          next.lastErrorMessageForId != null &&
          next.lastErrorMessageForId != previous?.lastErrorMessageForId) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.lastErrorMessageForId!)));
      }
    });
    final state = ref.watch(voicePlaybackControllerProvider);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final playing = state.isPlaying(messageId);
    final synthesizing = state.isSynthesizing(messageId);

    return IconButton(
      onPressed: synthesizing
          ? null
          : () => ref
                .read(voicePlaybackControllerProvider.notifier)
                .toggle(messageId, text),
      tooltip: playing ? 'Stop' : 'Read aloud',
      icon: synthesizing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(
              playing ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
              size: 16,
              color: color,
            ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      visualDensity: VisualDensity.compact,
    );
  }
}
