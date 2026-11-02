/// "Downloading your model · 42%" with a progress bar and the transfer line.
/// Shared by Today's brief card and Ask's no-model state so both say the same
/// thing while a model is on its way.
library;

import 'package:flutter/material.dart';

import '../../data/downloads/download_manager.dart';
import '../di/model_download.dart';
import '../theme/dhruva_theme_extension.dart';

class ModelDownloadLine extends StatelessWidget {
  const ModelDownloadLine({super.key, required this.progress});
  final DownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final f = downloadFraction(progress);
    final finishing = downloadFinishing(progress);
    final pct = f == null ? '' : ' · ${(f * 100).round()}%';
    final transfer = progress.transferLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          finishing ? 'Finishing up…' : 'Downloading your model$pct',
          key: const ValueKey('model-download-label'),
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tokens.spacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radius.sm),
          child: LinearProgressIndicator(
            key: const ValueKey('model-download-bar'),
            value: f,
          ),
        ),
        if (transfer != null) ...[
          SizedBox(height: tokens.spacing.xs),
          Text(
            transfer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
