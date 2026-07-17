import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../core/failures/app_failure.dart';
import '../db/database.dart';
import '../hf_api/quant_parser.dart';
import 'download_core.dart';
import 'storage_manager.dart';

/// Copies a user-picked GGUF file (selection itself — `file_picker` or
/// similar — is a UI concern, out of scope here) into [modelsDirectory],
/// validates its magic bytes, and registers it in [db]. [repoId] is
/// caller-supplied since a local import has no Hugging Face repo behind it
/// — the UI convention is `"local/<filename-without-extension>"`.
Future<InstalledModelInfo> importLocalGguf({
  required File sourceFile,
  required Directory modelsDirectory,
  required AppDatabase db,
  required String repoId,
  String? quant,
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

  await modelsDirectory.create(recursive: true);
  final fileName = p.basename(sourceFile.path);
  final destPath = p.join(modelsDirectory.path, fileName);

  final File copied;
  try {
    copied = await sourceFile.copy(destPath);
  } on FileSystemException catch (e) {
    throw StorageIoFailure(
      'failed to copy file into models directory',
      cause: e,
    );
  }
  final sizeBytes = await copied.length();

  final id = await db.upsertInstalledModel(
    InstalledModelsCompanion.insert(
      repoId: repoId,
      fileName: fileName,
      quant: Value(quant ?? extractQuantVariant(fileName)),
      sizeBytes: sizeBytes,
      localPath: destPath,
      downloadedAt: DateTime.now(),
    ),
  );

  return InstalledModelInfo(
    id: id,
    repoId: repoId,
    fileName: fileName,
    quant: quant ?? extractQuantVariant(fileName),
    sizeBytes: sizeBytes,
    localPath: destPath,
    gated: false,
    downloadedAt: DateTime.now(),
  );
}

Future<List<int>> _readHeader(File file, int length) async {
  final handle = await file.open();
  try {
    return await handle.read(length);
  } finally {
    await handle.close();
  }
}
