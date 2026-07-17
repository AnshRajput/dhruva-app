/// Shared setup for `features/voice` tests: writes dummy files at every path
/// [VoiceModelInstaller.isInstalled] checks for the catalog's VAD/ASR/TTS
/// entries, so controller tests can exercise the "models installed" path
/// without a real download (mirrors `test/voice/voice_model_installer_test
/// .dart`'s own file-planting pattern).
library;

import 'dart:io';

import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:path/path.dart' as p;

/// Plants every file [entry] needs directly under [modelsDirectory] (as if
/// it had already been downloaded + extracted), skipping the archive
/// download/extraction step entirely.
void installVoiceEntry(Directory modelsDirectory, VoiceCatalogEntry entry) {
  final root = entry.isArchive
      ? p.join(modelsDirectory.path, 'voice', entry.id)
      : modelsDirectory.path;
  for (final rel in entry.files.values) {
    final target = p.join(root, rel);
    if (rel.endsWith('espeak-ng-data')) {
      Directory(target).createSync(recursive: true);
    } else {
      File(target)
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
  }
}

/// Installs the whole catalog (VAD + ASR + both TTS voices) — the "hands-free
/// mode is fully ready" fixture.
void installAllVoiceModels(Directory modelsDirectory) {
  for (final entry in voiceModelCatalog) {
    installVoiceEntry(modelsDirectory, entry);
  }
}
