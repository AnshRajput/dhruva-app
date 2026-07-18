/// Shared loading/empty/error state widgets (T5 §6: every screen designs
/// all three, no blank fallthroughs). Spacing and typography come from
/// `DhruvaTokens` so every feature reads the same crafted states rather
/// than bare Material defaults. Lives in `core/` (next to `DhruvaLoader`)
/// so chat, characters and models_hub can all use it without the
/// cross-feature import ADR-002 bans.
library;

import 'package:flutter/material.dart';

import '../failures/failure_message.dart';
import '../theme/dhruva_theme_extension.dart';

class ErrorStateView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorStateView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final detail = describeError(error);
    // The generic fallback reads identically to the title, so show it only
    // when it adds something the title doesn't already say.
    final hasDetail = detail != kGenericFailureMessage;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: theme.colorScheme.error,
            ),
            SizedBox(height: tokens.spacing.md),
            Text(
              'Something went wrong',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (hasDetail) ...[
              SizedBox(height: tokens.spacing.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: tokens.spacing.lg),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyStateView({
    super.key,
    required this.message,
    this.icon = Icons.search_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            SizedBox(height: tokens.spacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
