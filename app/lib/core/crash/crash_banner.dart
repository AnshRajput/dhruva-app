import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/dhruva_theme_extension.dart';
import 'crash_actions.dart';
import 'crash_log.dart';

/// Next-launch nudge on the Chats home. Renders nothing unless there are
/// crash reports the user hasn't seen. Never sends anything by itself.
class CrashReportBanner extends ConsumerWidget {
  const CrashReportBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(unseenCrashReportsProvider).value ?? const [];
    final covered = !(ModalRoute.of(context)?.isCurrent ?? true);
    if (unseen.isEmpty || covered) {
      return const SizedBox(width: double.infinity);
    }

    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;

    Future<void> done() async {
      await ref.read(crashLogProvider).markSeen();
      ref.invalidate(unseenCrashReportsProvider);
    }

    return Container(
      key: const ValueKey('crash-banner'),
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
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: tokens.warning),
          SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Dhruva hit a problem last time. Send a crash report?',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('crash-dismiss'),
            onPressed: done,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: scheme.onSurfaceVariant,
            ),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            key: const ValueKey('crash-send'),
            onPressed: () async {
              await shareCrashReport(unseen);
              await done();
            },
            child: const Text('Send'),
          ),
          SizedBox(width: tokens.spacing.xs),
        ],
      ),
    );
  }
}
