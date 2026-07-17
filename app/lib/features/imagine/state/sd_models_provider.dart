/// Installed Stable Diffusion checkpoints (Loop 8 T2). No download/catalog
/// pipeline exists yet — see `core/di/providers.dart`'s
/// `sdModelsDirectoryProvider` doc — so "installed" just means "a file sits
/// in the sd models directory", scanned directly rather than tracked in
/// drift (there's no integrity/provenance metadata worth persisting for a
/// user-picked local file, unlike `InstalledModels`' downloaded GGUFs).
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';

/// Every file in the sd models directory, most-recently-added first.
final installedSdModelsProvider = FutureProvider<List<File>>((ref) async {
  final dir = await ref.watch(sdModelsDirectoryProvider.future);
  if (!dir.existsSync()) return const [];
  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  return files;
});

/// File types a Stable Diffusion checkpoint typically ships as.
const sdCheckpointTypeGroup = XTypeGroup(
  label: 'SD checkpoint',
  extensions: ['safetensors', 'ckpt', 'gguf'],
);

/// Copies [source] into the sd models directory and refreshes
/// [installedSdModelsProvider]. No hashing/validation — same trust level as
/// picking any other local file through the OS file picker.
Future<void> importSdCheckpoint(WidgetRef ref, File source) async {
  final dir = await ref.read(sdModelsDirectoryProvider.future);
  await source.copy(p.join(dir.path, p.basename(source.path)));
  ref.invalidate(installedSdModelsProvider);
}
