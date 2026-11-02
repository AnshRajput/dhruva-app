import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identity/app_identity.dart';
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
      // Its own breathing room above and below: it used to sit 12 px over the
      // greeting and crowd the header.
      margin: EdgeInsets.fromLTRB(
        tokens.spacing.md,
        tokens.spacing.sm,
        tokens.spacing.md,
        tokens.spacing.md,
      ),
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.md,
        tokens.spacing.md,
        tokens.spacing.sm,
        tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      // The sentence gets the full width on the first row; the two actions sit
      // on a second row, with Send tonal (the quiet one: it is the least
      // important thing on Today, so it must not be the loudest).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 20, color: tokens.warning),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${AppIdentity.shortName} hit a problem last time. Send a crash report?',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: tokens.spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('crash-dismiss'),
                  onPressed: done,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: const Text('Dismiss'),
                ),
                FilledButton.tonal(
                  key: const ValueKey('crash-send'),
                  onPressed: () async {
                    await shareCrashReport(unseen);
                    await done();
                  },
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
