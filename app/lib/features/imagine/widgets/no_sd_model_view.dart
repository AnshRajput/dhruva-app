/// Imagine's "no model" state (Loop 8 T2) — mirrors chat's
/// `NoModelInstalledView` shape, but the CTA is a local file import rather
/// than a browse-catalog push: no SD checkpoint download pipeline exists yet
/// (T1 only built the engine — see `sd_models_provider.dart`'s doc), so
/// there's nothing to browse to. Honest about the size reality instead.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/sd_models_provider.dart';

class NoSdModelView extends ConsumerWidget {
  const NoSdModelView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DhruvaStar(size: 72, color: theme.colorScheme.primary),
            SizedBox(height: tokens.spacing.lg),
            Text(
              'No image model installed',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Stable Diffusion checkpoints are large (2-4 GB). Download one '
              'to your computer (e.g. a "stable-diffusion-v1-5" '
              '.safetensors from Hugging Face), then import the file here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.lg),
            FilledButton(
              onPressed: () => _import(ref),
              child: const Text('Import a model file'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import(WidgetRef ref) async {
    final picked = await openFile(acceptedTypeGroups: [sdCheckpointTypeGroup]);
    if (picked == null) return;
    await importSdCheckpoint(ref, File(picked.path));
  }
}
