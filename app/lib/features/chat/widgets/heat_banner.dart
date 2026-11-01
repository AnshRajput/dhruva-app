/// Non-blocking "phone is getting hot" strip above the composer (battery &
/// heat guard). Never a dialog: the reply keeps streaming; the action is
/// optional.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';

class HeatBanner extends StatelessWidget {
  /// Null hides the action (no lighter model installed).
  final VoidCallback? onUseLighterModel;

  const HeatBanner({super.key, this.onUseLighterModel});

  static const message = 'Your phone is getting hot — replies may slow down';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('heat-banner'),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        color: theme.colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 20, color: tokens.warning),
            SizedBox(width: tokens.spacing.sm),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            if (onUseLighterModel != null)
              TextButton(
                onPressed: onUseLighterModel,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Use a lighter model'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small caption under a reply the heat guard stopped early.
class HeatStoppedNote extends StatelessWidget {
  const HeatStoppedNote({super.key});

  static const message =
      'Stopped early because your phone got too hot. Let it cool down, '
      'then try again.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 16, color: tokens.warning),
          SizedBox(width: tokens.spacing.xs),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
