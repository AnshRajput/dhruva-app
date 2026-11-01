/// Inline status around a reply that did not finish or has not started yet:
///
/// * [ReplyStatusNote] under a reply that was stopped, cut short or hit an
///   error part-way (D1), with a Continue action that resumes the same
///   message.
/// * [WarmUpStatus] while a send waits for the model (D3): "Warming up
///   Qwen 3B · 4 s", ticking once a second.
/// * [StalledTurnCard] when no first token arrived in time (D3): plain copy
///   with Stop / Try again.
///
/// Colors and text styles come from the theme; icons are ones the app
/// already ships (the tree-shaken icon font cannot gain glyphs via
/// Shorebird).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import 'brand_motif.dart';

/// Why a reply ended early.
enum ReplyEnd { stopped, cutShort, failed, tooHot }

extension ReplyEndCopy on ReplyEnd {
  /// The marker line shown under the reply.
  String get label => switch (this) {
    ReplyEnd.stopped => 'Stopped',
    ReplyEnd.cutShort => 'Cut short — reply was too long',
    ReplyEnd.failed => 'Stopped by an error',
    ReplyEnd.tooHot =>
      'Stopped early because your phone got too hot. Let it cool down, '
          'then continue.',
  };

  IconData get icon => switch (this) {
    ReplyEnd.stopped => Icons.stop_circle_outlined,
    ReplyEnd.cutShort => Icons.info_outline,
    ReplyEnd.failed => Icons.error_outline,
    ReplyEnd.tooHot => Icons.warning_amber,
  };
}

class ReplyStatusNote extends StatelessWidget {
  final ReplyEnd end;

  /// Resumes this reply. Null hides the button (an older reply, or a turn is
  /// already running).
  final VoidCallback? onContinue;

  /// "Continue" for a reply with text; "Try again" when nothing was written.
  final String actionLabel;

  const ReplyStatusNote({
    super.key,
    required this.end,
    this.onContinue,
    this.actionLabel = 'Continue',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final color = switch (end) {
      ReplyEnd.failed => theme.colorScheme.error,
      ReplyEnd.tooHot => tokens.warning,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return Padding(
      key: ValueKey('reply-note-${end.name}'),
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: tokens.spacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(end.icon, size: 16, color: color),
              SizedBox(width: tokens.spacing.xs),
              Flexible(
                child: Text(
                  end.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (onContinue != null)
            TextButton.icon(
              onPressed: onContinue,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: Icon(
                actionLabel == 'Continue' ? Icons.play_arrow : Icons.refresh,
                size: 18,
              ),
              label: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

/// "Warming up Qwen 3B · 4 s" while the model loads; once it is loaded the
/// usual typing indicator, with the elapsed time added after a few seconds so
/// a slow prefill does not look frozen.
class WarmUpStatus extends StatefulWidget {
  /// Short model name; null falls back to "the model".
  final String? modelName;

  /// True while the model file is still being loaded into memory.
  final bool loading;

  /// When the turn started (see `ChatThreadState.warmingSince`).
  final DateTime since;

  /// Clock, injectable for tests.
  final DateTime Function()? now;

  const WarmUpStatus({
    super.key,
    required this.modelName,
    required this.loading,
    required this.since,
    this.now,
  });

  /// Seconds before the elapsed time shows next to the typing indicator.
  static const showElapsedAfter = 5;

  @override
  State<WarmUpStatus> createState() => _WarmUpStatusState();
}

class _WarmUpStatusState extends State<WarmUpStatus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final now = (widget.now ?? DateTime.now)();
    final seconds = now.difference(widget.since).inSeconds.clamp(0, 86400);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final name = widget.modelName ?? 'the model';
    final Widget child;
    if (widget.loading) {
      child = Text('Warming up $name · $seconds s', style: style);
    } else if (seconds >= WarmUpStatus.showElapsedAfter) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TypingIndicator(),
          SizedBox(width: tokens.spacing.sm),
          Text('Thinking · $seconds s', style: style),
        ],
      );
    } else {
      child = const TypingIndicator();
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          key: const ValueKey('warm-up-status'),
          padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
          child: child,
        ),
      ),
    );
  }
}

/// No first token after the timeout: say so plainly and offer a way out.
class StalledTurnCard extends StatelessWidget {
  final VoidCallback onStop;
  final VoidCallback onTryAgain;

  /// Whole seconds waited, for the copy.
  final int seconds;

  const StalledTurnCard({
    super.key,
    required this.onStop,
    required this.onTryAgain,
    required this.seconds,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      key: const ValueKey('stalled-turn'),
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is taking longer than usual',
            style: theme.textTheme.titleSmall,
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            'Nothing has come back after $seconds seconds. Your phone may be '
            'busy or low on memory. You can keep waiting, stop, or start '
            'again.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          Wrap(
            spacing: tokens.spacing.sm,
            children: [
              FilledButton(
                onPressed: onTryAgain,
                child: const Text('Try again'),
              ),
              TextButton(onPressed: onStop, child: const Text('Stop')),
            ],
          ),
        ],
      ),
    );
  }
}
