import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../core/failures/app_failure.dart';
import '../db/database.dart';
import '../hf_api/quant_parser.dart';
import 'download_core.dart';
import 'storage_manager.dart';

/// Cooperative cancel flag for [importLocalGguf]; checked between chunks.
final class ImportCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
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

/// Copies a user-picked GGUF file (selection itself — `file_selector` — is a
/// UI concern) into [modelsDirectory], validates its magic bytes, and
/// registers it in [db]. [repoId] is caller-supplied since a local import has
/// no Hugging Face repo behind it — the UI convention is
/// `"local/<filename-without-extension>"`.
///
/// The copy is streamed (never buffered whole) into a `.part` file and renamed
/// into place only on success, so a failed/cancelled import leaves no partial
/// file and never clobbers an existing model. [freeBytes], when known, is
/// checked against the file size first. [onProgress] gets (copied, total).
Future<InstalledModelInfo> importLocalGguf({
  required File sourceFile,
  required Directory modelsDirectory,
  required AppDatabase db,
  required String repoId,
  String? quant,
  int? freeBytes,
  void Function(int copied, int total)? onProgress,
  ImportCancelToken? cancel,
}) async {
  if (!sourceFile.existsSync()) {
    throw const StorageNotFoundFailure('selected file does not exist');
  }

  final header = await _readHeader(sourceFile, ggufMagicBytes.length);
  if (!hasGgufMagic(header)) {
    throw const StorageCorruptFileFailure(
      'selected file is not a valid GGUF (missing "GGUF" magic bytes)',
    );
  }

  final total = await sourceFile.length();
  if (freeBytes != null && freeBytes < total) {
    throw StorageInsufficientSpaceFailure(
      'not enough free space to import this file',
      requiredBytes: total,
      availableBytes: freeBytes,
    );
  }

  await modelsDirectory.create(recursive: true);
  final fileName = p.basename(sourceFile.path);
  final destPath = p.join(modelsDirectory.path, fileName);
  final partFile = File('$destPath.part');

  try {
    // RandomAccessFile (not openWrite): its errors surface as plain awaited
    // failures instead of also firing on an unhandled IOSink.done.
    final out = await partFile.open(mode: FileMode.write);
    var copied = 0;
    try {
      await for (final chunk in sourceFile.openRead()) {
        if (cancel?.isCancelled ?? false) throw const ImportCancelled();
        await out.writeFrom(chunk);
        copied += chunk.length;
        onProgress?.call(copied, total);
      }
    } finally {
      await out.close();
    }
    if (cancel?.isCancelled ?? false) throw const ImportCancelled();
    await partFile.rename(destPath);
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
