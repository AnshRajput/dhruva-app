import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/dhruva_theme_extension.dart';
import 'shorebird_update_service.dart';

/// Shared copy for the banner and the Settings row.
const updIosReady = 'Update ready. Close and reopen Dhruva to finish.';

/// Compact one-row code-push nudge for the Chats home. Renders nothing unless
/// a patch is pending (always nothing on non-Shorebird builds), the user
/// hasn't chosen Later (6 h), and no route is covering this screen.
class ShorebirdUpdateBanner extends ConsumerWidget {
  const ShorebirdUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shorebirdUpdateProvider);
    final now = ref.watch(shorebirdNowProvider)();
    final covered = !(ModalRoute.of(context)?.isCurrent ?? true);
    final show = s.hasNudge && !s.snoozed(now) && !covered;
    final card = show
        ? _Card(key: const ValueKey('shorebird-banner'), state: s)
        : const SizedBox(width: double.infinity);
    // Reduce motion: swap instantly.
    if (MediaQuery.disableAnimationsOf(context)) return card;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: card,
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({super.key, required this.state});

  final ShorebirdUpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final n = ref.read(shorebirdUpdateProvider.notifier);

    final (
      String message,
      String? label,
      VoidCallback? onAction,
      bool later,
    ) = switch (state.phase) {
      ShorebirdPhase.available => (
        'Update available',
        'Update',
        n.download,
        true,
      ),
      ShorebirdPhase.downloading => ('Downloading update…', null, null, false),
      ShorebirdPhase.readyToRestart =>
        state.reopenByHand
            ? (updIosReady, null, null, true)
            : ('Update ready', 'Restart', n.restart, true),
      _ => ('Update failed', 'Retry', n.download, true),
    };
    final downloading = state.phase == ShorebirdPhase.downloading;
    final failed = state.phase == ShorebirdPhase.failed;
    final reduced = MediaQuery.disableAnimationsOf(context);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        tokens.spacing.md,
        tokens.spacing.xs,
        tokens.spacing.md,
        tokens.spacing.xs,
      ),
      padding: EdgeInsets.only(
        left: tokens.spacing.md,
        right: tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.system_update_alt_rounded,
                size: 20,
                color: failed ? tokens.warning : scheme.primary,
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
                    child: Text(
                      message,
                      key: const ValueKey('shorebird-message'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
              ),
              if (later)
                TextButton(
                  onPressed: n.snooze,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: const Text('Later'),
                ),
              if (label != null)
                FilledButton(
                  key: const ValueKey('shorebird-action'),
                  onPressed: onAction,
                  child: Text(label),
                ),
              SizedBox(width: tokens.spacing.xs),
            ],
          ),
          // Shorebird exposes no byte progress: indeterminate, never a fake %.
          if (downloading && !reduced)
            Padding(
              padding: EdgeInsets.only(
                right: tokens.spacing.md,
                bottom: tokens.spacing.sm,
              ),
              child: const LinearProgressIndicator(
                key: ValueKey('shorebird-progress'),
                minHeight: 4,
              ),
            ),
        ],
      ),
    );
  }
}
