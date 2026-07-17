/// Imagine's gallery tab (Loop 8 T2, D4): a grid of every saved generation,
/// tap for a full-screen view with prompt/params + save-share/delete.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/imagine/generated_image_repository.dart';
import '../state/gallery_provider.dart';

class ImagineGalleryView extends ConsumerWidget {
  const ImagineGalleryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(galleryProvider);
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return switch (gallery) {
      AsyncData(:final value) when value.isEmpty => const _EmptyGallery(),
      AsyncData(:final value) => GridView.builder(
        padding: EdgeInsets.all(tokens.spacing.sm),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: value.length,
        itemBuilder: (context, i) {
          final image = value[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImagineDetailView(image: image),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radius.sm),
              child: Image.file(
                File(image.filePath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Colors.black12),
              ),
            ),
          );
        },
      ),
      AsyncError() => const Center(child: Text("Couldn't load the gallery")),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

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
            DhruvaStar(size: 56, color: theme.colorScheme.onSurfaceVariant),
            SizedBox(height: tokens.spacing.md),
            Text(
              'No images yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: tokens.spacing.xs),
            Text(
              'Generate one on the Create tab — it lands here automatically.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImagineDetailView extends ConsumerWidget {
  final GeneratedImageInfo image;
  const ImagineDetailView({super.key, required this.image});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Scaffold(
      appBar: AppBar(
        title: Text('${image.width}×${image.height}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Share',
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                files: [XFile(image.filePath)],
                subject: 'Made with Dhruva AI',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radius.md),
                child: Image.file(File(image.filePath)),
              ),
              SizedBox(height: tokens.spacing.md),
              Text(image.prompt, style: Theme.of(context).textTheme.bodyLarge),
              if (image.negativePrompt.isNotEmpty) ...[
                SizedBox(height: tokens.spacing.xs),
                Text(
                  'Negative: ${image.negativePrompt}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              SizedBox(height: tokens.spacing.xs),
              Text(
                '${image.steps} steps · cfg ${image.cfgScale.toStringAsFixed(1)} '
                '· seed ${image.seed}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this image?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await deleteGeneratedImage(ref, image.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}
