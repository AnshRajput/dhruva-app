/// Per-file device verdict chip (T5 §3): renders the `ModelTier` a caller
/// already computed via `classifyModelTier`, plus a one-line explanation
/// ("needs ~6GB RAM, you have 8GB"). Pure/render-only — no classification
/// logic lives here, only display formatting.
library;

import 'package:flutter/material.dart';

import '../../../core/device_info/model_tier.dart';
import '../../../core/theme/dhruva_theme_extension.dart';

class ModelVerdictChip extends StatelessWidget {
  final ModelTier tier;
  final int fileSizeBytes;
  final int totalRamBytes;

  /// A vision model's paired mmproj projector size, added to [fileSizeBytes]
  /// for the explanation's RAM figure — mirrors `classifyModelTier`'s own
  /// combined-footprint accounting so the label matches the tier it's
  /// attached to. 0 for a plain text model.
  final int mmprojSizeBytes;

  const ModelVerdictChip({
    super.key,
    required this.tier,
    required this.fileSizeBytes,
    required this.totalRamBytes,
    this.mmprojSizeBytes = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<DhruvaTokens>()!;
    // mk-verdict (mock.css): a flat rounded pill, no Material chip chrome.
    // good = success tint, ok = primary-container, no = error-container.
    final (label, background, foreground, icon) = switch (tier) {
      ModelTier.comfortable => (
        'Comfortable',
        tokens.success.withValues(alpha: 0.24),
        tokens.success,
        Icons.check_circle,
      ),
      ModelTier.possible => (
        'Possible',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.info,
      ),
      ModelTier.notRecommended => (
        'Not recommended',
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.warning,
      ),
    };
    return Tooltip(
      message: explanation,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs / 2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(tokens.radius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            SizedBox(width: tokens.spacing.xs),
            // Flexible so a full-width list row shows the label in full while
            // the narrow recommended-rail card ellipsizes rather than
            // overflowing its 220px width.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get explanation {
    final neededGb = _formatGb(
      ramFloorBytesFor(fileSizeBytes + mmprojSizeBytes),
    );
    final haveGb = _formatGb(totalRamBytes);
    return 'needs ~${neededGb}GB RAM, you have ${haveGb}GB';
  }

  static String _formatGb(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return gb == gb.roundToDouble()
        ? gb.toStringAsFixed(0)
        : gb.toStringAsFixed(1);
  }
}
