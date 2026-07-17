/// AppBar model chip + live tok/s ticker (chat-spec.md §1.1).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/downloads/storage_manager.dart';

/// `bartowski/Llama-3.2-1B-Instruct-GGUF` → `Llama-3.2-1B-Instruct` (last
/// path segment of `repoId`, minus a trailing `-GGUF`).
String modelShortLabel(String repoId) {
  final segment = repoId.split('/').last;
  return segment.endsWith('-GGUF')
      ? segment.substring(0, segment.length - 5)
      : segment;
}

class ModelChip extends StatelessWidget {
  final InstalledModelInfo? model;
  final VoidCallback onTap;

  const ModelChip({super.key, required this.model, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final noModel = model == null;
    final background = noModel
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = noModel
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radius.full),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(tokens.radius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              noModel ? 'Pick a model' : modelShortLabel(model!.repoId),
              style: theme.textTheme.labelLarge?.copyWith(color: foreground),
            ),
            Icon(Icons.expand_more, size: 14, color: foreground),
          ],
        ),
      ),
    );
  }
}

/// Fades out `motion.fast`/`motion.standard` after generation ends,
/// replaced by nothing (AppBar right side goes empty between turns).
class TokPerSecTicker extends StatelessWidget {
  final double? tokPerSec;

  const TokPerSecTicker({super.key, required this.tokPerSec});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return AnimatedSwitcher(
      duration: tokens.motion.fast,
      switchInCurve: tokens.motion.standard,
      switchOutCurve: tokens.motion.standard,
      child: tokPerSec == null
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : Padding(
              key: const ValueKey('ticker'),
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
              child: Text(
                '${tokPerSec!.toStringAsFixed(1)} tok/s',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
    );
  }
}
