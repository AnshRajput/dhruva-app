/// Compact quality pill for the model detail screen's "Other versions
/// (advanced)" list. The band logic lives in `data/hf_api/quant_quality.dart`
/// (shared with the chat model picker and the Downloads list); re-exported here
/// so existing imports keep working.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/hf_api/quant_quality.dart';

export '../../../data/hf_api/quant_quality.dart';

/// Compact color-coded pill for a quant's quality band. Colour comes only from
/// the theme / [DhruvaTokens] (warning · primary · success · secondary),
/// tinted for the chip background — never a hardcoded value.
class QuantQualityChip extends StatelessWidget {
  final QuantQuality quality;
  const QuantQualityChip({super.key, required this.quality});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final color = switch (quality) {
      QuantQuality.lower => tokens.warning,
      QuantQuality.balanced => theme.colorScheme.primary,
      QuantQuality.higher => tokens.success,
      QuantQuality.nearLossless => theme.colorScheme.secondary,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Text(
        quality.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
