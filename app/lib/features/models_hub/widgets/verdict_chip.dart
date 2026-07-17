/// Per-file device verdict chip (T5 §3): renders the `ModelTier` a caller
/// already computed via `classifyModelTier`, plus a one-line explanation
/// ("needs ~6GB RAM, you have 8GB"). Pure/render-only — no classification
/// logic lives here, only display formatting.
library;

import 'package:flutter/material.dart';

import '../../../core/device_info/model_tier.dart';

class ModelVerdictChip extends StatelessWidget {
  final ModelTier tier;
  final int fileSizeBytes;
  final int totalRamBytes;

  const ModelVerdictChip({
    super.key,
    required this.tier,
    required this.fileSizeBytes,
    required this.totalRamBytes,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground, icon) = switch (tier) {
      ModelTier.comfortable => (
        'Comfortable',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle,
      ),
      ModelTier.possible => (
        'Possible',
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
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
      child: Chip(
        avatar: Icon(icon, size: 16, color: foreground),
        label: Text(label),
        backgroundColor: background,
        labelStyle: TextStyle(color: foreground),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  String get explanation {
    final neededGb = _formatGb(ramFloorBytesFor(fileSizeBytes));
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
