/// Hands-free conversation mode (Loop 6, T2/T3, D3) — the dedicated
/// screen/mode reachable from the chat app bar. Pure orchestration UI: it
/// knows nothing about `ChatController`/conversations (ADR-002 — this file
/// lives in `features/voice`, which never imports `features/chat`); the
/// actual "ask the engine, get a reply" step is [onUserUtterance], wired by
/// `core/router/app_router.dart` (the one composition root allowed to import
/// both features) from a closure `ChatThreadScreen` builds against its own
/// `ChatController`.
///
/// UI-PARITY loop: raised to match the website's VoiceMock — a central star
/// ORB with a soft gold glow (`mk-orb`), an animated waveform (`mk-wave`)
/// while listening/speaking, clear turn-taking status text, and the
/// "STT + TTS on-device" trust mark (`mk-trust`). The orb/star still pulses
/// per [HandsFreePhase] (Listening breathes slowly in `primary`, Thinking in
/// `secondary`, Speaking in `primary` again — the token `ColorScheme` has no
/// fourth "speaking" role), on the same "settle rather than bounce" motion
/// discipline (`DhruvaTokens.motion`) as the rest of the app.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/handsfree_controller.dart';

class HandsFreeScreen extends ConsumerStatefulWidget {
  final Future<String?> Function(String userText) onUserUtterance;

  const HandsFreeScreen({super.key, required this.onUserUtterance});

  @override
  ConsumerState<HandsFreeScreen> createState() => _HandsFreeScreenState();
}

class _HandsFreeScreenState extends ConsumerState<HandsFreeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() => ref
      .read(handsFreeControllerProvider.notifier)
      .start(onUserUtterance: widget.onUserUtterance);

  /// Re-runs [start] after resetting a stalled phase. `start()` early-returns
  /// unless `phase == idle`, so reset first — otherwise a fresh install done
  /// via the models hub is never picked up and the user stays stuck on
  /// "Voice models needed".
  Future<void> _retry() async {
    ref.read(handsFreeControllerProvider.notifier).reset();
    await _start();
  }

  /// The one guided step (WS5): open the models hub ON the Voice tab, then —
  /// when the user finishes installing and pops back onto this still-mounted
  /// screen — automatically re-check so hands-free just starts, no exit/re-
  /// enter dance.
  Future<void> _openVoiceModels() async {
    await context.push('/models?tab=voice');
    if (mounted) await _retry();
  }

  Future<void> _exit() async {
    await ref.read(handsFreeControllerProvider.notifier).stop();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final state = ref.watch(handsFreeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hands-free'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Exit hands-free',
          onPressed: _exit,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.lg),
          child: switch (state.phase) {
            HandsFreePhase.noModel => _NoModelView(
              onSetUpVoice: _openVoiceModels,
              onRetry: _retry,
            ),
            HandsFreePhase.permissionDenied => _PermissionDeniedView(
              onExit: _exit,
            ),
            _ => _ConversationView(state: state, onExit: _exit),
          },
        ),
      ),
    );
  }
}

class _ConversationView extends StatelessWidget {
  final HandsFreeState state;
  final VoidCallback onExit;
  const _ConversationView({required this.state, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    // The waveform reads as live audio only while a turn is actually flowing
    // through the mic/speaker (Listening or Speaking); it flattens to a quiet
    // baseline while the model is Thinking, so motion always means sound.
    final waveActive =
        state.phase == HandsFreePhase.listening ||
        state.phase == HandsFreePhase.speaking;
    // Scroll-safe: `lastAssistantText` is an unbounded spoken reply, so a
    // multi-sentence answer on a small phone would blow past the fixed
    // Column-with-Spacers height as a RenderFlex overflow. Centre the orb
    // when it all fits, scroll when it doesn't (same pattern as chat's
    // NoModelInstalledView) — IntrinsicHeight gives the Spacers a bounded
    // height to divide inside the scroll view.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                _VoiceOrb(phase: state.phase),
                SizedBox(height: tokens.spacing.xl),
                _VoiceWaveform(active: waveActive),
                SizedBox(height: tokens.spacing.xl),
                // Designer nit: a screen reader can't see the star pulse or the
                // waveform, so Listening -> Thinking -> Speaking is announced as it
                // happens, not just read once on focus.
                Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _phaseLabel(state.phase),
                        style: theme.textTheme.titleMedium,
                      ),
                      SizedBox(height: tokens.spacing.xs),
                      // mk-meta: the turn-taking hint — "your turn", or that a barge-in
                      // (voice interruption, wired for the Speaking phase) is possible.
                      Text(
                        _turnHint(state.phase),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: tokens.spacing.xl),
                Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.lastUserText != null)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: tokens.spacing.xs,
                          ),
                          child: Text(
                            '"${state.lastUserText}"',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (state.lastAssistantText != null)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: tokens.spacing.xs,
                          ),
                          child: Text(
                            state.lastAssistantText!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                    ],
                  ),
                ),
                if (state.errorMessage != null)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
                    child: Text(
                      state.errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const Spacer(),
                const _VoiceTrustMark(),
                SizedBox(height: tokens.spacing.md),
                OutlinedButton.icon(
                  onPressed: onExit,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('End hands-free'),
                ),
                SizedBox(height: tokens.spacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _phaseLabel(HandsFreePhase phase) => switch (phase) {
    HandsFreePhase.listening => 'Listening…',
    HandsFreePhase.thinking => 'Thinking…',
    HandsFreePhase.speaking => 'Speaking…',
    HandsFreePhase.idle => 'Starting…',
    HandsFreePhase.noModel => 'Voice models needed',
    HandsFreePhase.permissionDenied => 'Microphone access needed',
  };

  // Honest, calm turn-taking copy: barge-in is voice-driven (the mic stays
  // open through the Speaking phase — see HandsFreeController), so the
  // interrupt affordance is "speak", not a tap. Kept deliberately low-key
  // ("speak to interrupt", not "any time") because the barge-in logic is
  // wired + unit-tested but the on-device acoustic path — the mic hearing you
  // over the speaker without echo cancellation — is unverified (orchestra/
  // RISKS.md R11). So the UI invites the action without promising it always
  // lands: don't over-promise a behaviour we can't yet stand behind on a real
  // phone.
  String _turnHint(HandsFreePhase phase) => switch (phase) {
    HandsFreePhase.listening => 'your turn — speak now',
    HandsFreePhase.thinking => 'thinking on your device…',
    HandsFreePhase.speaking => 'speak to interrupt',
    _ => '',
  };
}

/// The central star ORB (VoiceMock `mk-orb`): the brand star inside a soft
/// gold radial glow that breathes continuously in every active phase — the
/// glow color and breathing rate are the only things that change per phase,
/// so the *shape* of "something is happening" never resets between turns.
class _VoiceOrb extends StatefulWidget {
  final HandsFreePhase phase;
  const _VoiceOrb({required this.phase});

  @override
  State<_VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<_VoiceOrb>
    with SingleTickerProviderStateMixin {
  // Bootstrap value only — no `BuildContext`/theme at field-initializer time
  // (same precedent as chat's `TypingIndicator`/`MicButton`);
  // didChangeDependencies immediately overwrites this with the real theme
  // value.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _rawDurationFor(widget.phase),
  )..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = _durationFor(context, widget.phase);
  }

  @override
  void didUpdateWidget(covariant _VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _controller.duration = _durationFor(context, widget.phase);
    }
  }

  static Duration _rawDurationFor(HandsFreePhase phase) => switch (phase) {
    HandsFreePhase.listening => TokenMotionDuration.pulseSlow,
    HandsFreePhase.thinking => TokenMotionDuration.pulseMedium,
    // Same cadence as chat's typing indicator (`motion.moderate`) — both
    // mark "the AI is actively outputting."
    HandsFreePhase.speaking => TokenMotionDuration.moderate,
    _ => TokenMotionDuration.pulseSlow,
  };

  static Duration _durationFor(BuildContext context, HandsFreePhase phase) {
    final motion = Theme.of(context).extension<DhruvaTokens>()!.motion;
    return switch (phase) {
      HandsFreePhase.listening => motion.pulseSlow,
      HandsFreePhase.thinking => motion.pulseMedium,
      HandsFreePhase.speaking => motion.moderate,
      _ => motion.pulseSlow,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (widget.phase) {
      HandsFreePhase.thinking => scheme.secondary,
      HandsFreePhase.speaking => scheme.primary,
      _ => scheme.primary,
    };
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Breathe via a transform (paint-time), never the box's own size —
        // no layout property is animated (design-tokens.json motion rule).
        final scale = 1.0 + (t * 0.06);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.40 + t * 0.12),
                  color.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.24 + t * 0.14),
                  blurRadius: 44,
                  spreadRadius: 4,
                ),
              ],
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Center(child: DhruvaStar(size: 46, color: color)),
          ),
        );
      },
    );
  }
}

/// Animated waveform (VoiceMock `mk-wave`): a row of secondary-tinted bars
/// that ripple like live audio while [active], collapsing to a quiet flat
/// baseline otherwise. Bars are scaled (paint-time), never resized, so no
/// layout property animates.
class _VoiceWaveform extends StatefulWidget {
  final bool active;
  const _VoiceWaveform({required this.active});

  @override
  State<_VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<_VoiceWaveform>
    with SingleTickerProviderStateMixin {
  // Per-bar max heights lifted straight from VoiceMock's deterministic
  // silhouette so the resting shape matches the website exactly.
  static const _profile = <double>[
    8,
    14,
    20,
    12,
    22,
    16,
    10,
    18,
    24,
    14,
    9,
    17,
    21,
    12,
    7,
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TokenMotionDuration.pulseMedium,
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = Theme.of(
      context,
    ).extension<DhruvaTokens>()!.motion.pulseMedium;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final color = theme.colorScheme.secondary;
    const maxHeight = 26.0;
    return SizedBox(
      height: maxHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _profile.length; i++) ...[
                if (i > 0) SizedBox(width: tokens.spacing.xs / 2),
                _WaveBar(
                  maxHeight: maxHeight,
                  barHeight: _profile[i],
                  // A travelling sine gives the "audio" ripple; when inactive
                  // every bar collapses to a dot-thin baseline.
                  scaleY: widget.active
                      ? 0.28 +
                            0.72 *
                                ((math.sin(2 * math.pi * t + i * 0.55) + 1) / 2)
                      : 0.12,
                  color: color,
                  radius: tokens.radius.full,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WaveBar extends StatelessWidget {
  final double maxHeight;
  final double barHeight;
  final double scaleY;
  final Color color;
  final double radius;

  const _WaveBar({
    required this.maxHeight,
    required this.barHeight,
    required this.scaleY,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 3,
      height: maxHeight,
      child: Center(
        child: Transform.scale(
          scaleY: scaleY,
          child: Container(
            width: 3,
            height: barHeight,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      ),
    );
  }
}

/// VoiceMock `mk-trust`: the star's gold accent + "STT + TTS on-device" — the
/// voice-screen twin of chat's "Runs 100% on your device" trust mark (which
/// lives in `features/chat` and can't be imported here per ADR-002, so this
/// is a small deliberate sibling, same precedent as `core/theme/brand_star`).
class _VoiceTrustMark extends StatelessWidget {
  const _VoiceTrustMark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DhruvaStar(size: 12, color: theme.colorScheme.primary),
        SizedBox(width: tokens.spacing.xs),
        Text(
          'STT + TTS on-device',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NoModelView extends StatelessWidget {
  /// Opens the models hub on the Voice tab and re-checks on return (the one
  /// guided step). [onRetry] re-checks in place for the case the user
  /// installed the models some other way.
  final VoidCallback onSetUpVoice;
  final VoidCallback onRetry;

  const _NoModelView({required this.onSetUpVoice, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DhruvaStar(size: 72, color: theme.colorScheme.primary),
          SizedBox(height: tokens.spacing.lg),
          Text(
            'Voice models needed',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: tokens.spacing.sm),
          Text(
            'Hands-free needs a small voice bundle — turn-taking, '
            'speech-to-text, and a voice. Install it in one tap, then come '
            'straight back here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          FilledButton(
            // Nothing to tear down here — `start()` returns before opening
            // the mic whenever it lands on `noModel` (see `HandsFreeController
            // .start`), so this is a plain forward navigation, not an exit.
            // The AppBar's own close button is still there for "never mind."
            // Returns to this still-mounted screen and re-checks automatically.
            onPressed: onSetUpVoice,
            child: const Text('Set up voice'),
          ),
          SizedBox(height: tokens.spacing.sm),
          TextButton(
            onPressed: onRetry,
            child: const Text('Already installed? Try again'),
          ),
        ],
      ),
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  final VoidCallback onExit;
  const _PermissionDeniedView({required this.onExit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic_off_outlined,
            size: 72,
            color: theme.colorScheme.error,
          ),
          SizedBox(height: tokens.spacing.lg),
          Text(
            'Microphone access needed',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: tokens.spacing.sm),
          Text(
            'Dhruva needs the microphone to hear you. Enable it in your '
            'device\'s app settings, then try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          FilledButton(onPressed: onExit, child: const Text('Close')),
        ],
      ),
    );
  }
}
