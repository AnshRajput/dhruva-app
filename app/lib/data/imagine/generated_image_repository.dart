/// Persistence for the Imagine gallery (Loop 8 T2) — the `GeneratedImages`
/// drift table, surfaced without the drift-generated row type so
/// `features/imagine` never imports drift directly (ADR-002 precedent:
/// `StorageManager`'s `InstalledModelInfo`, `ChatRepository`'s
/// `ConversationSummary`).
library;

import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/failures/app_failure.dart';
import '../db/database.dart';

/// One `GeneratedImages` row.
final class GeneratedImageInfo {
  final int id;
  final String prompt;
  final String negativePrompt;
  final String filePath;
  final int width;
  final int height;
  final int steps;
  final int seed;
  final double cfgScale;
  final DateTime createdAt;

  const GeneratedImageInfo({
    required this.id,
    required this.prompt,
    required this.negativePrompt,
    required this.filePath,
    required this.width,
    required this.height,
    required this.steps,
    required this.seed,
    required this.cfgScale,
    required this.createdAt,
  });
}

final class GeneratedImageRepository {
  final AppDatabase _db;
  const GeneratedImageRepository({required AppDatabase db}) : _db = db;

  /// Newest first — the gallery's default read order.
  Future<List<GeneratedImageInfo>> list() async {
    final rows = await (_db.select(
      _db.generatedImages,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    return rows.map(_toInfo).toList(growable: false);
  }

  Future<int> insert({
    required String prompt,
    required String negativePrompt,
    required String filePath,
    required int width,
    required int height,
    required int steps,
    required int seed,
    required double cfgScale,
  }) {
    return _db
        .into(_db.generatedImages)
        .insert(
          GeneratedImagesCompanion.insert(
            prompt: prompt,
            negativePrompt: Value(negativePrompt),
            filePath: filePath,
            width: width,
            height: height,
            steps: steps,
            seed: seed,
            cfgScale: cfgScale,
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Deletes the PNG on disk and the row. Throws [StorageNotFoundFailure] if
  /// [id] isn't a known row, [StorageIoFailure] if the file exists but can't
  /// be deleted (row is left in place, same "don't lose track of an orphan"
  /// precedent as `StorageManager.delete`).
  Future<void> delete(int id) async {
    final row = await (_db.select(
      _db.generatedImages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StorageNotFoundFailure('no generated image with id $id');
    }
    final file = File(row.filePath);
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      throw StorageIoFailure('failed to delete ${row.filePath}', cause: e);
    }
    await (_db.delete(_db.generatedImages)..where((t) => t.id.equals(id))).go();
  }

  GeneratedImageInfo _toInfo(GeneratedImage row) => GeneratedImageInfo(
    id: row.id,
    prompt: row.prompt,
    negativePrompt: row.negativePrompt,
    filePath: row.filePath,
    width: row.width,
    height: row.height,
    steps: row.steps,
    seed: row.seed,
    cfgScale: row.cfgScale,
    createdAt: row.createdAt,
  );
}
