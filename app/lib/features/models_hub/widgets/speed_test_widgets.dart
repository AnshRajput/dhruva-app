/// Installed-tab speed test UI: per-model row, run status bar with Cancel, and
/// the one-time "Run a 20-second speed test?" offer. All state lives in
/// `speed_test_controller.dart` / `speedResultsProvider`; these are render +
/// dispatch only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/speed_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/speed_label_chip.dart';
import '../../../data/benchmark/speed_result.dart';
import '../../../data/benchmark/speed_test_runner.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../data/models/starter_catalog.dart';
import '../state/speed_test_controller.dart';

String _phaseText(SpeedTestPhase? phase) => switch (phase) {
  SpeedTestPhase.loading || null => 'Loading the model…',
  SpeedTestPhase.prefilling => 'Reading a short passage…',
  SpeedTestPhase.decoding => 'Measuring how fast it writes…',
};

/// Chip + "Test speed" action for one installed model, or its progress.
class SpeedTestRow extends ConsumerWidget {
  final InstalledModelInfo model;
  const SpeedTestRow({super.key, required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final key = speedKey(model.repoId, model.fileName);
    final result = ref.watch(speedResultsProvider).value?[key];
    final test = ref.watch(speedTestControllerProvider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (test.runningKey == key) {
      return Padding(
        padding: EdgeInsets.only(top: tokens.spacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _phaseText(test.phase),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!reduceMotion) ...[
              SizedBox(height: tokens.spacing.xs),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      );
    }
    if (test.queued.contains(key)) {
      return Padding(
        padding: EdgeInsets.only(top: tokens.spacing.xs),
        child: Text(
          'Waiting for its turn…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final failure = test.failures[key];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: tokens.spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SpeedLabelChip(result: result),
            TextButton(
              onPressed: test.active
                  ? null
                  : () => ref.read(speedTestControllerProvider.notifier).run([
                      model,
                    ]),
              child: Text(result == null ? 'Test speed' : 'Test again'),
            ),
          ],
        ),
        if (failure != null)
          Text(
            failure,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// Shown above the list while a run is active (also carries the "can't start"
/// notice when chat is busy). One Cancel for the whole run.
class SpeedTestStatusBar extends ConsumerWidget {
  const SpeedTestStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final test = ref.watch(speedTestControllerProvider);

    if (!test.active) {
      final notice = test.notice;
      if (notice == null) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.xs,
        ),
        child: Text(
          notice,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }
    final step = (test.completed + 1).clamp(1, test.total);
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.xs,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.md,
          tokens.spacing.sm,
          tokens.spacing.sm,
          tokens.spacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  test.total > 1
                      ? 'Testing speed · model $step of ${test.total}\n'
                            '${_phaseText(test.phase)}'
                      : 'Testing speed\n${_phaseText(test.phase)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(speedTestControllerProvider.notifier).cancel(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-time, dismissible "Run a 20-second speed test?" for the newest
/// downloaded/imported model that has no result yet.
class SpeedTestOfferBanner extends ConsumerWidget {
  final List<InstalledModelInfo> installed;
  const SpeedTestOfferBanner({super.key, required this.installed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final offers = ref.watch(speedTestOfferProvider);
    final results = ref.watch(speedResultsProvider).value;
    final active = ref.watch(speedTestControllerProvider).active;
    if (results == null) return const SizedBox.shrink();

    InstalledModelInfo? target;
    for (final key in offers.reversed) {
      final m = installed
          .where((m) => speedKey(m.repoId, m.fileName) == key)
          .firstOrNull;
      if (m != null && !results.containsKey(key)) {
        target = m;
        break;
      }
    }
    if (target == null) return const SizedBox.shrink();
    final model = target;
    final key = speedKey(model.repoId, model.fileName);
    final dismiss = ref.read(speedTestOfferProvider.notifier).dismiss;

    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.xs,
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run a 20-second speed test?',
              style: theme.textTheme.titleSmall,
            ),
            SizedBox(height: tokens.spacing.xs),
            Text(
              'See how fast ${friendlyModelName(model.repoId)} runs on your '
              'phone before you start chatting.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            Wrap(
              spacing: tokens.spacing.sm,
              children: [
                FilledButton(
                  onPressed: active
                      ? null
                      : () {
                          dismiss(key);
                          ref.read(speedTestControllerProvider.notifier).run([
                            model,
                          ]);
                        },
                  child: const Text('Run test'),
                ),
                TextButton(
                  onPressed: () => dismiss(key),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
