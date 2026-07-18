/// Per-variant quality/effectiveness guidance for the model detail screen's
/// "All quantizations (advanced)" list. The human's video asked for "which
/// variant is how much effective" — so alongside each quant's file SIZE we
/// show a QUALITY band so the size↔quality tradeoff is legible, not just the
/// megabytes.
///
/// IMPORTANT: this is a HEURISTIC from the quant's name (e.g. `Q4_K_M`,
/// `IQ3_M`, `Q8_0`, `F16`), NOT a measured benchmark — smaller quants trade
/// accuracy for size, larger ones approach the full-precision model. The copy
/// is labelled as guidance for exactly that reason. Mirrors the same quant-
/// family reasoning `pickDefaultQuant` uses to default to `Q4_K_M`.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';

/// The four quality bands a GGUF quant name maps to, each with a compact chip
/// label and a one-line "what this means".
enum QuantQuality {
  lower(
    'Smaller · lower quality',
    'Fits tight storage, but noticeably less accurate.',
  ),
  balanced(
    'Balanced · recommended',
    'The community default — good quality for its size.',
  ),
  higher(
    'Higher quality · larger',
    'Closer to the original; needs more space and RAM.',
  ),
  nearLossless(
    'Near-lossless · largest',
    'Barely distinguishable from full precision; biggest files.',
  );

  const QuantQuality(this.label, this.blurb);

  /// Short pill copy, e.g. "Balanced · recommended".
  final String label;

  /// One-line "what this means" shown under the chip.
  final String blurb;
}

/// Classify a quant [label] into a [QuantQuality] band by parsing its bit
/// level. Float families (`F16`/`F32`/`BF16`) are effectively lossless; Q/IQ
/// families split on the bit count (≤3 lower · 4 balanced · 5-6 higher · 8+
/// near-lossless). Unrecognized labels fall back to [QuantQuality.balanced]
/// (a neutral guess rather than a scary one).
QuantQuality classifyQuantQuality(String label) {
  final l = label.toUpperCase();
  if (l.startsWith('F16') || l.startsWith('F32') || l.startsWith('BF16')) {
    return QuantQuality.nearLossless;
  }
  // First digit run after an optional `I` and the `Q` prefix is the bit level.
  final match = RegExp(r'I?Q(\d+)').firstMatch(l);
  if (match == null) return QuantQuality.balanced;
  final bits = int.parse(match.group(1)!);
  if (bits <= 3) return QuantQuality.lower;
  if (bits == 4) return QuantQuality.balanced;
  if (bits <= 6) return QuantQuality.higher;
  return QuantQuality.nearLossless;
}

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
