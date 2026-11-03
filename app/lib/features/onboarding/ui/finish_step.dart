/// Onboarding step 4: "You're set". The model download carries on in a strip
/// at the top, and the morning-brief notification is offered as an opt-in
/// switch (off by default). It reuses the Settings > Notifications permission
/// flow (`setMorningBrief`); the notification text stays generic, and tapping
/// it opens Today.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/intents/app_settings.dart';
import '../../../core/notifications/morning_brief.dart';
import '../../../core/notifications/morning_brief_toggle.dart';
import '../../../core/settings/bool_pref.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/onboarding_controller.dart';
import 'connect_step.dart';

class FinishStep extends ConsumerStatefulWidget {
  const FinishStep({
    super.key,
    required this.onDone,
    required this.onRetryDownload,
  });

  /// Marks onboarding complete and goes to Today.
  final Future<void> Function() onDone;

  /// Restarts the model download after a failure.
  final VoidCallback onRetryDownload;

  @override
  ConsumerState<FinishStep> createState() => _FinishStepState();
}

class _FinishStepState extends ConsumerState<FinishStep> {
  /// The OS refused the notification permission when the switch was turned on.
  bool _blocked = false;

  Future<void> _setBrief(bool on) async {
    if (!on) setState(() => _blocked = false);
    final ok = await setMorningBrief(ref, on: on);
    if (mounted && on) setState(() => _blocked = !ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final briefOn = ref.watch(morningBriefEnabledProvider).value ?? false;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: OnboardingStepBars(active: 3),
          ),
          SizedBox(height: tokens.spacing.md),
          _DownloadStrip(onRetry: widget.onRetryDownload),
          SizedBox(height: tokens.spacing.lg),
          Text('You\'re set', style: theme.textTheme.headlineLarge),
          SizedBox(height: tokens.spacing.md),
          Text(
            'One more thing, if you like.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(tokens.radius.lg),
            ),
            child: SwitchListTile.adaptive(
              key: const ValueKey('finish-morning-brief'),
              secondary: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Morning brief'),
              subtitle: const Text(
                'A daily nudge to read your brief. It only says '
                '\u201c$morningBriefBody\u201d, never anything from your '
                'calendar or messages.',
              ),
              value: briefOn,
              onChanged: _setBrief,
            ),
          ),
          if (_blocked) ...[
            SizedBox(height: tokens.spacing.sm),
            Row(
              key: const ValueKey('finish-brief-blocked'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 20),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Text(
                    'Notifications are off for this app. Allow them in your '
                    'phone settings, then turn this on again.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  key: const ValueKey('finish-open-settings'),
                  onPressed: () => ref.read(openAppSettingsProvider)(),
                  child: const Text('Open settings'),
                ),
              ],
            ),
          ],
          SizedBox(height: tokens.spacing.xl),
          FilledButton(
            key: const ValueKey('finish-continue'),
            onPressed: () => widget.onDone(),
            child: const Text('Go to Today'),
          ),
        ],
      ),
    );
  }
}

/// The model download, carried along: progress while it runs, "ready" when it
/// lands, and the same recovery as the download step when it fails.
class _DownloadStrip extends ConsumerWidget {
  const _DownloadStrip({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(onboardingDownloadControllerProvider).value;
    final status = dl?.status ?? OnboardingDownloadStatus.idle;
    if (status == OnboardingDownloadStatus.idle) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final failed = status == OnboardingDownloadStatus.failed;
    final done = status == OnboardingDownloadStatus.installed;
    final pct = ((dl?.progress ?? 0) * 100).round();
    final finishing = dl?.finishing ?? false;
    final label = failed
        ? "Download didn't finish. ${dl?.errorMessage ?? ''}".trim()
        : done
        ? 'Your model is ready.'
        : finishing
        ? 'Finishing up…'
        : pct > 0
        ? 'Your model is downloading in the background · $pct%'
        : 'Getting your model ready in the background…';
    return DecoratedBox(
      key: const ValueKey('connect-download-strip'),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : done
                      ? Icons.check_circle
                      : Icons.downloading_rounded,
                  size: 18,
                  color: failed
                      ? scheme.error
                      : done
                      ? tokens.success
                      : scheme.primary,
                ),
                SizedBox(width: tokens.spacing.sm),
                Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
                if (failed)
                  TextButton(
                    key: const ValueKey('connect-download-retry'),
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
              ],
            ),
            if (!failed && !done)
              Padding(
                padding: EdgeInsets.only(top: tokens.spacing.xs),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radius.full),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: (dl?.progress ?? 0) > 0 ? dl!.progress : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
