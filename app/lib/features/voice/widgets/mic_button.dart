/// Hold-to-talk button (Loop 6, T2, D1): press down starts capture, release
/// finalizes into the composer via [onFinalized]. Pulses while listening —
/// the chat-spec.md-style "recording indicator" this build brief calls for
/// (no bounce/spring curves, per the token set's motion rules).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/voice_input_controller.dart';

class MicButton extends ConsumerStatefulWidget {
  final ValueChanged<String> onFinalized;
  final VoidCallback onNoModel;
  final VoidCallback onPermissionDenied;

  const MicButton({
    super.key,
    required this.onFinalized,
    required this.onNoModel,
    required this.onPermissionDenied,
  });

  @override
  ConsumerState<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends ConsumerState<MicButton>
    with SingleTickerProviderStateMixin {
  // Bootstrap value only — no `BuildContext`/theme at field-initializer
  // time (same precedent as chat's `TypingIndicator`); didChangeDependencies
  // immediately overwrites this with the real theme value below.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: TokenMotionDuration.pulseMedium,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pulse.duration = Theme.of(
      context,
    ).extension<DhruvaTokens>()!.motion.pulseMedium;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // Only animates while actually listening — an unconditional `repeat()`
  // would run forever and never let `pumpAndSettle` (or a real device's
  // battery) rest once the idle/no-model/permission-denied states are
  // reached.
  void _syncPulse(bool listening) {
    if (listening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!listening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  Future<void> _onTapDown() async {
    final notifier = ref.read(voiceInputControllerProvider.notifier);
    await notifier.startHold();
    final phase = ref.read(voiceInputControllerProvider).phase;
    if (!mounted) return;
    if (phase == VoiceInputPhase.noModel) widget.onNoModel();
    if (phase == VoiceInputPhase.permissionDenied) {
      widget.onPermissionDenied();
    }
  }

  Future<void> _onTapUp() async {
    final notifier = ref.read(voiceInputControllerProvider.notifier);
    final text = await notifier.endHold();
    if (!mounted) return;
    if (text.trim().isNotEmpty) widget.onFinalized(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final input = ref.watch(voiceInputControllerProvider);
    final listening = input.phase == VoiceInputPhase.listening;
    _syncPulse(listening);

    return Semantics(
      button: true,
      label: listening ? 'Recording — release to stop' : 'Hold to talk',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs),
        child: GestureDetector(
          onTapDown: (_) => _onTapDown(),
          onTapUp: (_) => _onTapUp(),
          onTapCancel: _onTapUp,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final scale = listening ? 1.0 + (_pulse.value * 0.15) : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                listening ? Icons.mic : Icons.mic_none_outlined,
                color: listening
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
