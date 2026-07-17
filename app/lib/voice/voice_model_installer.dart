/// Post-download install step for voice models (Loop 6, D3).
///
/// Voice models flow through the SAME resumable pipeline as GGUF models: the
/// `DownloadManager` fetches the file into `modelsDirectory` (resumable,
/// integrity-checked, storage-guarded, drift-registered). sherpa's ASR/TTS
/// models ship as `.tar.bz2` bundles of several files, so an archive entry
/// needs one extra step after download — extraction — which lives here,
/// deliberately separate from the tested-to-death `DownloadManager` core.
/// Single-file models (the Silero VAD `.onnx`) skip extraction entirely.
///
/// The pure `extractTarBz2` function is what gets exhaustive unit tests (with a
/// synthetic archive); the real download + real bundles are exercised by the
/// dev-machine integration test.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'voice_model_catalog.dart';
import 'voice_service.dart';

/// Extract a `.tar.bz2` [archive] into [destDir], returning the list of files
/// written (relative to [destDir]).
///
/// Zip-slip safe: an entry whose path escapes [destDir] (e.g. `../../etc/x`) is
/// rejected — this is a trust boundary (the archive came off the network).
///
/// ponytail: whole-archive-in-memory bz2 decode (the `archive` package has no
/// streaming bzip2). Bundles are ≤ ~200 MB and this runs once per install, off
/// the root isolate via [extractTarBz2Async]. Upgrade path: a streaming bz2
/// decoder if a much larger bundle ever ships.
List<String> extractTarBz2(File archive, Directory destDir) {
  final bytes = archive.readAsBytesSync();
  final tarBytes = BZip2Decoder().decodeBytes(bytes);
  final decoded = TarDecoder().decodeBytes(tarBytes);

  destDir.createSync(recursive: true);
  final destRoot = p.canonicalize(destDir.path);
  final written = <String>[];

  for (final entry in decoded) {
    final target = p.canonicalize(p.join(destDir.path, entry.name));
    // zip-slip: the resolved target must stay inside destDir.
    if (target != destRoot && !p.isWithin(destRoot, target)) {
      throw VoiceModelLoadFailure(
        'archive entry escapes install dir: "${entry.name}"',
      );
    }
    if (entry.isFile) {
      final out = File(target);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(entry.content as List<int>);
      written.add(p.relative(target, from: destRoot));
    } else {
      Directory(target).createSync(recursive: true);
    }
  }
  return written;
}

/// [extractTarBz2] on a background isolate so the heavy bz2 decode never blocks
/// the root isolate (ADR-002: inference/downloads/heavy work off the UI thread).
Future<List<String>> extractTarBz2Async(
  String archivePath,
  String destDirPath,
) {
  return Isolate.run(
    () => extractTarBz2(File(archivePath), Directory(destDirPath)),
  );
}

/// Resolves where a catalog entry's files live and turns them into the neutral
/// [VoiceService] model configs. Owns the `voice/` subtree under the models
/// directory; the `DownloadManager` still owns the download itself.
final class VoiceModelInstaller {
  /// The app's models directory (same one `DownloadManager` writes into).
  final Directory modelsDirectory;

  VoiceModelInstaller({required this.modelsDirectory});

  /// Per-entry install root. Archives extract here; single-file models are
  /// referenced from `modelsDirectory` directly (see [_fileRoot]).
  Directory installDir(VoiceCatalogEntry entry) =>
      Directory(p.join(modelsDirectory.path, 'voice', entry.id));

  /// True once the entry's files are present and resolvable.
  bool isInstalled(VoiceCatalogEntry entry) {
    try {
      _verify(resolvePaths(entry));
      return true;
    } on VoiceFailure {
      return false;
    }
  }

  /// Extract [entry]'s downloaded archive (at `modelsDirectory/<archiveName>`)
  /// into its install dir, then delete the archive to reclaim space. No-op for
  /// single-file entries. Runs the extraction off the root isolate.
  Future<void> install(VoiceCatalogEntry entry) async {
    if (!entry.isArchive) return;
    final archive = File(p.join(modelsDirectory.path, entry.archiveName));
    if (!archive.existsSync()) {
      throw VoiceModelLoadFailure('archive not downloaded: ${archive.path}');
    }
    final dir = installDir(entry);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await extractTarBz2Async(archive.path, dir.path);
    await _safeDelete(archive);
    _verify(resolvePaths(entry));
  }

  /// The absolute paths of [entry]'s files, keyed as in [VoiceCatalogEntry.
  /// files]. Does not check existence — use [isInstalled]/[_verify] for that.
  Map<String, String> resolvePaths(VoiceCatalogEntry entry) {
    final root = entry.isArchive ? installDir(entry).path : _fileRoot(entry);
    return {for (final e in entry.files.entries) e.key: p.join(root, e.value)};
  }

  String _fileRoot(VoiceCatalogEntry entry) => modelsDirectory.path;

  void _verify(Map<String, String> paths) {
    for (final path in paths.values) {
      if (!File(path).existsSync() && !Directory(path).existsSync()) {
        throw VoiceModelLoadFailure('missing voice model file: $path');
      }
    }
  }

  /// Build the ASR config for an installed ASR entry.
  AsrModelConfig asrConfig(VoiceCatalogEntry entry, {String language = ''}) {
    assert(entry.role == VoiceModelRole.asr);
    final paths = resolvePaths(entry);
    _verify(paths);
    return AsrModelConfig(
      type: AsrModelType.whisper,
      encoder: paths['encoder']!,
      decoder: paths['decoder']!,
      tokens: paths['tokens']!,
      language: language,
    );
  }

  /// Build the TTS config for an installed TTS entry.
  TtsModelConfig ttsConfig(VoiceCatalogEntry entry) {
    assert(entry.role == VoiceModelRole.tts);
    final paths = resolvePaths(entry);
    _verify(paths);
    return TtsModelConfig(
      type: TtsModelType.vits,
      model: paths['model']!,
      tokens: paths['tokens']!,
      dataDir: paths['dataDir'] ?? '',
    );
  }

  /// Build the VAD config for an installed VAD entry.
  VadConfig vadConfig(VoiceCatalogEntry entry) {
    assert(entry.role == VoiceModelRole.vad);
    final paths = resolvePaths(entry);
    _verify(paths);
    return VadConfig(model: paths['model']!);
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Best-effort space reclaim; a leftover archive is a disk nit.
    }
  }
}
