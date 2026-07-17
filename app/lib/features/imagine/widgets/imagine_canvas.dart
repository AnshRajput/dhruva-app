/// The square generation "canvas" (Loop 8 T2) — matches ImagineMock's
/// `mk-canvas`: an idle state washed in the brand's tertiary/primary/
/// secondary gradient, replaced by a progress ring mid-run and the finished
/// image once done. One aspect-ratio box, one `Positioned.fill` swap per
/// phase — no separate widget per state, they're too small to be worth it.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/imagine_generation_controller.dart';
import 'gen_progress_ring.dart';

class ImagineCanvas extends StatelessWidget {
  final GenerationState state;
  final VoidCallback onCancel;

  const ImagineCanvas({super.key, required this.state, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.tertiary.withValues(alpha: 0.35),
                scheme.primary.withValues(alpha: 0.30),
                scheme.secondary.withValues(alpha: 0.35),
              ],
            ),
          ),
          child: Center(child: _content(context, tokens)),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, DhruvaTokens tokens) {
    final theme = Theme.of(context);
    switch (state.phase) {
      case GenPhase.idle:
        return Icon(
          Icons.auto_awesome_outlined,
          size: 40,
          color: theme.colorScheme.onSurfaceVariant,
        );
      case GenPhase.loadingModel:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: tokens.spacing.sm),
            Text('Loading model…', style: theme.textTheme.labelLarge),
          ],
        );
      case GenPhase.generating:
        final step = state.progressStep ?? 0;
        final total = state.progressTotal ?? 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GenProgressRing(
              progress: total == 0 ? 0 : step / total,
              onCancel: onCancel,
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Step $step / $total',
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      case GenPhase.done:
        final png = state.resultPng;
        if (png == null) {
          return const Icon(Icons.image_outlined, size: 40);
        }
        return Image.memory(
          png,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      case GenPhase.cancelled:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, color: theme.colorScheme.onSurfaceVariant),
            SizedBox(height: tokens.spacing.xs),
            const Text('Cancelled'),
          ],
        );
      case GenPhase.error:
        return Padding(
          padding: EdgeInsets.all(tokens.spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              SizedBox(height: tokens.spacing.xs),
              Text(
                state.errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
    }
  }
}
