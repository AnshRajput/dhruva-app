/// The Imagine gallery's read list (Loop 8 T2) — thin `FutureProvider`
/// wrapper over `GeneratedImageRepository`, same shape as
/// `installedModelsProvider` in chat. `ImagineGenerationController`
/// invalidates this on a successful save; `deleteGeneratedImage` does the
/// same after a delete.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/imagine/generated_image_repository.dart';

final galleryProvider = FutureProvider<List<GeneratedImageInfo>>((ref) {
  return ref.watch(generatedImageRepositoryProvider).list();
});

Future<void> deleteGeneratedImage(WidgetRef ref, int id) async {
  await ref.read(generatedImageRepositoryProvider).delete(id);
  ref.invalidate(galleryProvider);
}
