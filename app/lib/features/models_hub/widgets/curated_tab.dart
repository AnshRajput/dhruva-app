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

    // Show the WHOLE curated set with per-item verdicts (unlike the old rail
    // which hid non-fitting models) — the section isn't titled "Recommended",
    // so an honest "Not recommended" chip on a too-big pick is information,
    // not a contradiction, and satisfies WS1's "verdicts are correct". When
    // RAM is known, lead with the best-fitting picks; otherwise keep the
    // catalog's smallest-first order.
    final models = starterModelCatalog.toList();
    if (ram != null) {
      int tierIndex(StarterModel m) => classifyModelTier(
        fileSizeBytes: m.approxSizeBytes,
        totalRamBytes: ram,
      ).index;
      models.sort((a, b) {
        final byTier = tierIndex(a).compareTo(tierIndex(b));
        return byTier != 0
            ? byTier
            : a.approxSizeBytes.compareTo(b.approxSizeBytes);
      });
    }

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
        for (final model in models)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.md,
              vertical: tokens.spacing.xs,
            ),
            child: CuratedModelCard(model: model, totalRamBytes: ram),
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
