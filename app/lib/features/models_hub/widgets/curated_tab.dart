/// The DEFAULT Models experience (PRD v0.3 WS1): the curated catalog of
/// phone-verified models, each a `CuratedModelCard` with a one-tap download,
/// sorted best-fit-first for THIS device. The raw Hugging Face firehose is
/// demoted to the secondary "Search all of Hugging Face (advanced)" button at
/// the foot of the list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device_info/model_tier.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/recommended_models_provider.dart';
import 'curated_model_card.dart';

class CuratedTab extends ConsumerWidget {
  const CuratedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final ram = ref.watch(deviceMemoryProvider).value?.totalBytes;

    // Segment so the screen never contradicts its own promise (critic HIGH):
    // models that FIT this phone go under "Runs great on your phone" with the
    // best pick badged "Recommended"; anything the device can't run
    // comfortably drops into a COLLAPSED "Larger models" group instead of
    // sitting under a "runs great" header with a red "Not recommended" chip.
    // When RAM is unknown we can't judge, so everything stays in the main list.
    ModelTier? tierOf(StarterModel m) => ram == null
        ? null
        : classifyModelTier(
            fileSizeBytes: m.approxSizeBytes,
            totalRamBytes: ram,
          );

    final fitting = <StarterModel>[];
    final larger = <StarterModel>[];
    for (final m in starterModelCatalog) {
      if (tierOf(m) == ModelTier.notRecommended) {
        larger.add(m);
      } else {
        fitting.add(m);
      }
    }
    if (ram != null) {
      // Best-fit first (comfortable before possible), then smallest — so the
      // recommended pick is the fastest comfortable model to first chat.
      fitting.sort((a, b) {
        final byTier = tierOf(a)!.index.compareTo(tierOf(b)!.index);
        return byTier != 0
            ? byTier
            : a.approxSizeBytes.compareTo(b.approxSizeBytes);
      });
      larger.sort((a, b) => a.approxSizeBytes.compareTo(b.approxSizeBytes));
    }
    final recommended = fitting.isNotEmpty ? fitting.first : null;

    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.md,
            tokens.spacing.sm,
            tokens.spacing.md,
            tokens.spacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Runs great on your phone',
                style: theme.textTheme.titleMedium,
              ),
              SizedBox(height: tokens.spacing.xs),
              Text(
                'Hand-picked models verified to run on-device. One tap picks '
                'the right size and downloads — no jargon.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final model in fitting)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.md,
              vertical: tokens.spacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (identical(model, recommended)) ...[
                  _RecommendedBadge(),
                  SizedBox(height: tokens.spacing.xs),
                ],
                CuratedModelCard(model: model, totalRamBytes: ram),
              ],
            ),
          ),
        if (larger.isNotEmpty)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
              title: Text('Larger models', style: theme.textTheme.titleSmall),
              subtitle: Text(
                'May be slow or too big for your phone',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                for (final model in larger)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.md,
                      vertical: tokens.spacing.xs,
                    ),
                    child: CuratedModelCard(model: model, totalRamBytes: ram),
                  ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.md,
            tokens.spacing.sm,
            tokens.spacing.md,
            tokens.spacing.md,
          ),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.travel_explore, size: 18),
            label: const Text('Search all of Hugging Face (advanced)'),
            onPressed: () => context.push('/models/search'),
          ),
        ),
      ],
    );
  }
}

/// The same "Recommended" affordance onboarding uses, carried onto the best
/// device-fitting pick in Discover (critic HIGH: Discover had no highlighted
/// pick). Gold pill, star-primary — reads as "start here".
class _RecommendedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(tokens.spacing.sm),
      ),
      child: Text(
        'Recommended',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
