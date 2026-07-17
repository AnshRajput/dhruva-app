/// "Recommended for your device" rail (Amendment 4c): shown above search
/// results in the models hub's Search tab, only while the query is empty
/// (models_hub_screen.dart). Each card is the starter catalog entry
/// annotated with this device's tier verdict, reusing the same
/// `classifyModelTier` + `ModelVerdictChip` the model detail screen uses —
/// no parallel verdict logic here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device_info/model_tier.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/recommended_models_provider.dart';
import 'verdict_chip.dart';

class RecommendedRail extends ConsumerWidget {
  const RecommendedRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final memory = ref.watch(deviceMemoryProvider);

    // Device-aware ranking (Phase B, D5): once RAM is known, sort so the
    // models that run best on THIS device (comfortable → possible → not
    // recommended) come first. Before RAM resolves, keep declaration order.
    final ram = memory.value?.totalBytes;
    final models = ram == null
        ? starterModelCatalog
        : (starterModelCatalog.toList()..sort((a, b) {
            int rank(StarterModel m) => classifyModelTier(
              fileSizeBytes: m.approxSizeBytes,
              totalRamBytes: ram,
            ).index;
            return rank(a).compareTo(rank(b));
          }));

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            child: Text(
              'Recommended for your device',
              style: theme.textTheme.titleSmall,
            ),
          ),
          SizedBox(height: tokens.spacing.xs),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
              itemCount: models.length,
              separatorBuilder: (context, i) =>
                  SizedBox(width: tokens.spacing.sm),
              itemBuilder: (context, i) {
                final model = models[i];
                return _RecommendedCard(
                  model: model,
                  tier: switch (memory) {
                    AsyncData(:final value) => classifyModelTier(
                      fileSizeBytes: model.approxSizeBytes,
                      totalRamBytes: value.totalBytes,
                    ),
                    _ => null,
                  },
                  totalRamBytes: memory.value?.totalBytes,
                );
              },
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final StarterModel model;

  /// Null while the device RAM reading is still loading (or failed) — the
  /// card renders without a verdict chip rather than blocking on it; size
  /// alone is still useful.
  final ModelTier? tier;
  final int? totalRamBytes;

  const _RecommendedCard({
    required this.model,
    required this.tier,
    required this.totalRamBytes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Semantics(
      button: true,
      label:
          '${model.displayName}, ${_formatBytes(model.approxSizeBytes)}'
          '${tier == null ? '' : ', ${_tierLabel(tier!)}'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        onTap: () =>
            context.push('/models/repo/${Uri.encodeComponent(model.repoId)}'),
        child: Container(
          width: 220,
          padding: EdgeInsets.all(tokens.spacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(tokens.radius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                model.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              // Wrap, not Row: a "Not recommended" chip + size label can
              // exceed the card's width on narrower text scales — Wrap
              // drops to a second line instead of overflowing the RenderFlex.
              Wrap(
                spacing: tokens.spacing.xs,
                runSpacing: tokens.spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _formatBytes(model.approxSizeBytes),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (tier != null)
                    ModelVerdictChip(
                      tier: tier!,
                      fileSizeBytes: model.approxSizeBytes,
                      totalRamBytes: totalRamBytes!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _tierLabel(ModelTier tier) => switch (tier) {
  ModelTier.comfortable => 'comfortable on your device',
  ModelTier.possible => 'possible on your device',
  ModelTier.notRecommended => 'not recommended on your device',
};

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}
