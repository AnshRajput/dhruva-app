import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../core/failures/app_failure.dart';
import '../db/database.dart';
import '../hf_api/quant_parser.dart';
import 'download_core.dart';
import 'model_file_channel.dart';
import 'storage_manager.dart';

/// Cooperative cancel flag for [importLocalGguf]. [whenCancelled] lets the
/// native copy (which runs outside Dart) be told to stop.
final class ImportCancelToken {
  final _done = Completer<void>();
  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// Thrown when [ImportCancelToken.cancel] stops a copy; the partial file is
/// already cleaned up. Not an [AppFailure] — cancelling isn't an error.
final class ImportCancelled implements Exception {
  const ImportCancelled();
}

/// True if a file named [fileName] is already in [modelsDirectory] (the UI
/// asks replace-or-skip before calling [importLocalGguf]).
bool localImportExists(Directory modelsDirectory, String fileName) =>
    File(p.join(modelsDirectory.path, fileName)).existsSync();

/// Imports a user-picked GGUF ([picked], from [ModelFileChannel.pick]) into
/// [modelsDirectory], validates its magic bytes, and registers it in [db].
/// [repoId] is caller-supplied since a local import has no Hugging Face repo
/// behind it — the UI convention is `"local/<filename-without-extension>"`.
///
/// The copy runs natively in chunks (never buffered whole, never through the
/// Dart heap) into a `.part` file and is renamed into place only after the
/// magic check, so a failed/cancelled import leaves no partial file and never
/// clobbers an existing model. [freeBytes], when known, is checked against
/// the file size first (native also reports `no_space` if the disk fills
/// mid-copy). [onProgress] gets (copied, total).
Future<InstalledModelInfo> importLocalGguf({
  required PickedModelFile picked,
  required ModelFileChannel channel,
  required Directory modelsDirectory,
  required AppDatabase db,
  required String repoId,
  String? quant,
  int? freeBytes,
  void Function(int copied, int total)? onProgress,
  ImportCancelToken? cancel,
}) async {
  final fileName = picked.name;
  if (fileName.isEmpty || !fileName.toLowerCase().endsWith('.gguf')) {
    throw const StorageCorruptFileFailure('selected file is not a .gguf');
  }
  final total = picked.size;
  if (freeBytes != null && total > 0 && freeBytes < total) {
    throw StorageInsufficientSpaceFailure(
      'not enough free space to import this file',
      requiredBytes: total,
      availableBytes: freeBytes,
    );
  }

  await modelsDirectory.create(recursive: true);
  final destPath = p.join(modelsDirectory.path, fileName);
  final partFile = File('$destPath.part');

  try {
    await channel.copy(
      picked,
      partFile.path,
      onProgress: onProgress,
      cancelled: cancel?.whenCancelled,
    );
    if (cancel?.isCancelled ?? false) throw const ImportCancelled();
    final header = await _readHeader(partFile, ggufMagicBytes.length);
    if (!hasGgufMagic(header)) {
      throw const StorageCorruptFileFailure(
        'selected file is not a valid GGUF (missing "GGUF" magic bytes)',
      );
    }
    await partFile.rename(destPath);
  } on ModelFileException catch (e) {
    await _deleteQuietly(partFile);
    throw switch (e.code) {
      'cancelled' => const ImportCancelled(),
      'no_space' => StorageInsufficientSpaceFailure(
        'not enough free space to import this file',
        requiredBytes: total,
        availableBytes: freeBytes ?? 0,
      ),
      _ => StorageIoFailure(
        'failed to copy file into models directory',
        cause: e,
      ),
    };
  } on FileSystemException catch (e) {
    await _deleteQuietly(partFile);
    throw StorageIoFailure(
      'failed to copy file into models directory',
      cause: e,
    );
  } catch (_) {
    await _deleteQuietly(partFile);
    rethrow;
  }
  final sizeBytes = await File(destPath).length();
  final resolvedQuant = quant ?? extractQuantVariant(fileName);
  final now = DateTime.now();

  final id = await db.upsertInstalledModel(
    InstalledModelsCompanion.insert(
      repoId: repoId,
      fileName: fileName,
      quant: Value(resolvedQuant),
      sizeBytes: sizeBytes,
      localPath: destPath,
      downloadedAt: now,
    ),
  );

  return InstalledModelInfo(
    id: id,
    repoId: repoId,
    fileName: fileName,
    quant: resolvedQuant,
    sizeBytes: sizeBytes,
    localPath: destPath,
    gated: false,
    downloadedAt: now,
  );
}

Future<void> _deleteQuietly(File f) async {
  try {
    if (f.existsSync()) await f.delete();
  } on FileSystemException {
    // best effort
  }
}

Future<List<int>> _readHeader(File file, int length) async {
  final handle = await file.open();
  try {
    return await handle.read(length);
  } finally {
    await handle.close();
  }
}
