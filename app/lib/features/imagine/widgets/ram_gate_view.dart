/// The "flagged OFF below the RAM floor" state (Loop 8 T2 gate). Shown
/// instead of the whole Imagine feature — including the gallery — when the
/// device's total RAM is under `SdImageGenService.recommendedMinRamBytes`.
/// An honest explanation, not a broken Generate button: SD's ~2-4GB working
/// set on top of the OS just doesn't fit.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';

class ImagineRamGateView extends StatelessWidget {
  final int deviceRamBytes;
  final int floorBytes;
  const ImagineRamGateView({
    super.key,
    required this.deviceRamBytes,
    required this.floorBytes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final deviceGb = (deviceRamBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    final floorGb = (floorBytes / (1024 * 1024 * 1024)).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Imagine')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DhruvaStar(size: 72, color: theme.colorScheme.onSurfaceVariant),
              SizedBox(height: tokens.spacing.lg),
              Text(
                'Needs a higher-memory device',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.spacing.sm),
              Text(
                'On-device image generation needs about $floorGb GB of RAM. '
                'This device has $deviceGb GB, so Imagine stays off here — '
                'better than a Generate button that fails partway through.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
