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
    final ram = memory.value?.totalBytes;

    // The rail must never contradict itself: a section titled "Recommended
    // for your device" showing "Not recommended" cards reads as broken.
    // So, once RAM is known, show ONLY the models that actually fit
    // (comfortable → possible), best-first. If NONE fit (a low-RAM device),
    // fall back to the smallest models under an honest header + a gentle
    // "may be slow" note instead of an alarming red "Not recommended" chip.
    final ({List<StarterModel> models, String header, bool fallback}) rail;
    if (ram == null) {
      rail = (
        models: starterModelCatalog.toList(),
        header: 'Recommended for your device',
        fallback: false,
      );
    } else {
      ModelTier tierOf(StarterModel m) => classifyModelTier(
        fileSizeBytes: m.approxSizeBytes,
        totalRamBytes: ram,
      );
      final fitting =
          starterModelCatalog
              .where((m) => tierOf(m) != ModelTier.notRecommended)
              .toList()
            ..sort((a, b) => tierOf(a).index.compareTo(tierOf(b).index));
      if (fitting.isNotEmpty) {
        rail = (
          models: fitting,
          header: 'Recommended for your device',
          fallback: false,
        );
      } else {
        // Nothing fits — offer the smallest few to try, honestly framed.
        final smallest = starterModelCatalog.toList()
          ..sort((a, b) => a.approxSizeBytes.compareTo(b.approxSizeBytes));
        rail = (
          models: smallest.take(3).toList(),
          header: 'Smallest models to try',
          fallback: true,
        );
      }
    }
    final models = rail.models;

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            child: Text(rail.header, style: theme.textTheme.titleSmall),
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
                  // In fallback mode every card is too big for the device;
                  // show a gentle note, not a red "Not recommended" chip.
                  fallback: rail.fallback,
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

  /// True when this card is in the "Smallest models to try" fallback (nothing
  /// fits the device): render a muted "may be slow" note instead of the red
  /// "Not recommended" verdict chip, which would contradict the section.
  final bool fallback;

  const _RecommendedCard({
    required this.model,
    required this.tier,
    required this.totalRamBytes,
    this.fallback = false,
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
                  if (fallback)
                    Text(
                      'May be slow',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.warning,
                      ),
                    )
                  else if (tier != null)
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
