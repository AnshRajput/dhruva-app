/// Speed label pill shared by the Models hub Installed tab and the chat model
/// picker (`core/` so neither feature imports the other). Render-only: the
/// label comes from `speedLabelFor`; colors come from the theme/tokens.
library;

import 'package:flutter/material.dart';

import '../../data/benchmark/speed_label.dart';
import '../../data/benchmark/speed_result.dart';
import '../theme/dhruva_theme_extension.dart';

class SpeedLabelChip extends StatelessWidget {
  /// Null renders the neutral "Not tested" state.
  final SpeedResult? result;

  const SpeedLabelChip({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<DhruvaTokens>()!;
    final r = result;
    final (text, background, foreground, icon) = switch (r?.label) {
      null => (
        'Not tested',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        null,
      ),
      SpeedLabel.fast => (
        SpeedLabel.fast.message,
        tokens.success.withValues(alpha: 0.24),
        tokens.success,
        Icons.bolt,
      ),
      SpeedLabel.usable => (
        SpeedLabel.usable.message,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check,
      ),
      SpeedLabel.slow => (
        SpeedLabel.slow.message,
        tokens.warning.withValues(alpha: 0.24),
        tokens.warning,
        Icons.warning_amber,
      ),
    };
    return Tooltip(
      message: r == null
          ? 'Run a speed test to see how fast this model is on your phone'
          : 'About ${r.decodeTps.toStringAsFixed(1)} tokens per second',
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
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              SizedBox(width: tokens.spacing.xs),
            ],
            // Flexible + no maxLines: the "Slow ... try a smaller model" copy
            // wraps rather than clipping on a narrow row or large text scale.
            Flexible(
              child: Text(
                text,
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
}
