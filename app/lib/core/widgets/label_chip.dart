/// A small neutral label pill ("Android", an app name). Capped in width so a
/// very long label ellipsises instead of overflowing its row.
library;

import 'package:flutter/material.dart';

import '../theme/dhruva_theme_extension.dart';

class LabelChip extends StatelessWidget {
  const LabelChip(this.label, {super.key, this.maxWidth = 160});
  final String label;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radius.full),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.sm,
            vertical: tokens.spacing.xs / 2,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}
