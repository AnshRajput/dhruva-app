/// Hands-free conversation mode (Loop 6, T2/T3, D3) — the dedicated
/// screen/mode reachable from the chat app bar. Pure orchestration UI: it
/// knows nothing about `ChatController`/conversations (ADR-002 — this file
/// lives in `features/voice`, which never imports `features/chat`); the
/// actual "ask the engine, get a reply" step is [onUserUtterance], wired by
/// `core/router/app_router.dart` (the one composition root allowed to import
/// both features) from a closure `ChatThreadScreen` builds against its own
/// `ChatController`.
///
/// State indicator: the brand star (`core/theme/brand_star.dart`) pulses at
/// a different rate/color per [HandsFreePhase] — Listening breathes slowly
/// in `primary`, Thinking pulses faster in `secondary`, Speaking pulses in
/// `tertiary`-equivalent (`colorScheme.primary` again, at a brighter scale,
/// since the token `ColorScheme` has no fourth "speaking" role to spare) —
/// the same "settle rather than bounce" motion discipline (`DhruvaTokens
/// .motion`) as the rest of the app.
library;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(handsFreeControllerProvider.notifier)
          .start(onUserUtterance: widget.onUserUtterance);
    });
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
            HandsFreePhase.noModel => const _NoModelView(),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        _PhaseIndicator(phase: state.phase),
        SizedBox(height: tokens.spacing.lg),
        // Designer nit: a screen reader can't see the star pulse change
        // rate/color, so Listening -> Thinking -> Speaking needs to be
        // announced as it happens, not just read once on focus.
        Semantics(
          liveRegion: true,
          child: Text(
            _phaseLabel(state.phase),
            style: theme.textTheme.titleMedium,
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
                  padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
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
                  padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
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
        OutlinedButton.icon(
          onPressed: onExit,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('End hands-free'),
        ),
        SizedBox(height: tokens.spacing.lg),
      ],
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
}

/// The star pulses continuously in every active phase — rate/color are the
/// only thing that changes, so the *shape* of "something is happening" never
/// resets between turns (chat-spec.md's own typing indicator does the
/// analogous thing with three small stars; this is the one-big-star,
/// whole-screen version of the same motif).
class _PhaseIndicator extends StatefulWidget {
  final HandsFreePhase phase;
  const _PhaseIndicator({required this.phase});

  @override
  State<_PhaseIndicator> createState() => _PhaseIndicatorState();
}

class _PhaseIndicatorState extends State<_PhaseIndicator>
    with SingleTickerProviderStateMixin {
  // Bootstrap value only — no `BuildContext`/theme at field-initializer
  // time (same precedent as chat's `TypingIndicator`/`MicButton`);
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
  void didUpdateWidget(covariant _PhaseIndicator oldWidget) {
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
    final scheme = Theme.of(context).colorScheme;
    final color = switch (widget.phase) {
      HandsFreePhase.thinking => scheme.secondary,
      HandsFreePhase.speaking => scheme.primary,
      _ => scheme.primary,
    };
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final scale = widget.phase == HandsFreePhase.thinking
            ? 1.0 + (t * 0.08)
            : 1.0 + (t * 0.18);
        return Opacity(
          opacity: 0.55 + (t * 0.45),
          child: Transform.scale(
            scale: scale,
            child: DhruvaStar(size: 96, color: color),
          ),
        );
      },
    );
  }
}

class _NoModelView extends StatelessWidget {
  const _NoModelView();

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
            'Hands-free mode needs a turn-taking, speech-to-text, and '
            'text-to-speech model installed — download them from the '
            'models hub\'s Voice tab.',
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
            onPressed: () => context.push('/models'),
            child: const Text('Open models hub'),
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
