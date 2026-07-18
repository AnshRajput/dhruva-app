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

  /// WS3: true while `ChatController.ensureModelLoaded` is mapping the model
  /// into memory — the chip shows a spinner + "Loading…" so the wait for the
  /// first token reads as "the model is warming up," not "nothing happened."
  final bool loading;
  final VoidCallback onTap;

  const ModelChip({
    super.key,
    required this.model,
    this.loading = false,
    required this.onTap,
  });

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

    final label = noModel
        ? 'Pick a model'
        : loading
        ? 'Loading…'
        : modelShortLabel(model!.repoId);

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
            if (loading && !noModel) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
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
                // mk-tokps (mock.css): the live ticker is the one gold accent
                // in the app bar — `--color-primary`, not the quiet variant —
                // so the "your device is doing this, right now" number reads
                // as the hero metric it is.
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
    );
  }
}
