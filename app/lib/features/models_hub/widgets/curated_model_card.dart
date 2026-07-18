/// One curated-catalog entry (PRD v0.3 WS1): friendly name, one-line
/// "best for…", size, a device verdict, and ONE download button that
/// auto-picks the right Q4-class quant (via `ListingDownloadController`, keyed
/// by repoId — the same one-tap path search rows use). Tapping the card body
/// opens the detail screen for users who want the full quant picker; the
/// trailing button is the seamless default-quant path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device_info/model_tier.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/listing_download_controller.dart';
import '../state/recommended_models_provider.dart';
import 'listing_download_button.dart';
import 'verdict_chip.dart';

class CuratedModelCard extends ConsumerWidget {
  final StarterModel model;

  /// Device RAM, or null while the reading is loading — the card still shows
  /// name/best-for/size without blocking on the verdict.
  final int? totalRamBytes;

  const CuratedModelCard({
    super.key,
    required this.model,
    required this.totalRamBytes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final ram = totalRamBytes;

    // Surface a failed one-tap download's reason on the card itself — the
    // trailing button collapses to a bare Retry icon otherwise, leaving a
    // gated/no-quant/too-big failure with no explanation (the search row
    // renders this same message; the curated card must not be the dead end).
    final dl = ref
        .watch(listingDownloadControllerProvider)
        .value?[model.repoId];
    final errorMessage = dl?.status == ListingModelStatus.failed
        ? dl?.errorMessage
        : null;
    final tier = ram == null
        ? null
        : classifyModelTier(
            fileSizeBytes: model.approxSizeBytes,
            totalRamBytes: ram,
          );

    return Semantics(
      button: true,
      label:
          '${model.displayName}. ${model.bestFor}. '
          '${_formatBytes(model.approxSizeBytes)}'
          '${tier == null ? '' : '. ${_tierLabel(tier)}'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        onTap: () =>
            context.push('/models/repo/${Uri.encodeComponent(model.repoId)}'),
        child: Container(
          padding: EdgeInsets.all(tokens.spacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(tokens.radius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (model.isVision) ...[
                          SizedBox(width: tokens.spacing.xs),
                          _VisionBadge(),
                        ],
                      ],
                    ),
                    SizedBox(height: tokens.spacing.xs),
                    Text(
                      model.bestFor,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.sm),
                    Wrap(
                      spacing: tokens.spacing.sm,
                      runSpacing: tokens.spacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _formatBytes(model.approxSizeBytes),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (tier != null && ram != null)
                          ModelVerdictChip(
                            tier: tier,
                            fileSizeBytes: model.approxSizeBytes,
                            totalRamBytes: ram,
                          ),
                      ],
                    ),
                    if (dl?.download?.transferLabel case final detail?
                        when dl?.status == ListingModelStatus.downloading) ...[
                      SizedBox(height: tokens.spacing.xs),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (errorMessage != null) ...[
                      SizedBox(height: tokens.spacing.xs),
                      Text(
                        errorMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              ListingDownloadButton(
                repoId: model.repoId,
                displayName: model.displayName,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisionBadge extends StatelessWidget {
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
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 12,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          SizedBox(width: tokens.spacing.xs),
          Text(
            'Vision',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _tierLabel(ModelTier tier) => switch (tier) {
  ModelTier.comfortable => 'Comfortable on your device',
  ModelTier.possible => 'Possible on your device',
  ModelTier.notRecommended => 'Not recommended on your device',
};

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}
