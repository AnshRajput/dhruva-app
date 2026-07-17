import 'dart:io';

import 'package:drift/drift.dart' show NullsOrder, OrderingTerm, Value;

import '../../core/device_info/device_info_service.dart';
import '../../core/failures/app_failure.dart';
import '../db/database.dart';
import 'download_core.dart';

/// One row of `InstalledModels`, surfaced without the drift-generated type
/// so `features/` never imports drift directly (ADR-002: `data/` owns
/// persistence, `features/` consumes repository-shaped results).
final class InstalledModelInfo {
  final int id;
  final String repoId;
  final String fileName;
  final String? quant;
  final int sizeBytes;
  final String? sha256;
  final String localPath;
  final String? license;
  final bool gated;
  final DateTime downloadedAt;
  final DateTime? lastUsedAt;

  const InstalledModelInfo({
    required this.id,
    required this.repoId,
    required this.fileName,
    this.quant,
    required this.sizeBytes,
    this.sha256,
    required this.localPath,
    this.license,
    required this.gated,
    required this.downloadedAt,
    this.lastUsedAt,
  });
}

/// Everything about installed models that isn't "is it downloading" —
/// that's `DownloadManager`. This is the surface `features/models_hub`'s
/// storage screen consumes: list, delete, total usage, free-space guard.
final class StorageManager {
  final AppDatabase _db;
  final DeviceInfoService _deviceInfo;

  const StorageManager({
    required AppDatabase db,
    required DeviceInfoService deviceInfo,
  }) : _db = db,
       _deviceInfo = deviceInfo;

  /// Most-recently-used first (nulls — never loaded — sort last), then by
  /// file name — the Loop-4 model picker's default read order.
  Future<List<InstalledModelInfo>> listInstalledModels() async {
    final query = _db.select(_db.installedModels)
      ..orderBy([
        (t) => OrderingTerm.desc(t.lastUsedAt, nulls: NullsOrder.last),
        (t) => OrderingTerm.asc(t.fileName),
      ]);
    final rows = await query.get();
    return rows.map(_toInfo).toList(growable: false);
  }

  /// A single installed model by drift row id, or null if it isn't
  /// installed (already deleted, or never was).
  Future<InstalledModelInfo?> getInstalledModel(int id) async {
    final row = await (_db.select(
      _db.installedModels,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toInfo(row);
  }

  /// Stamps `lastUsedAt` to now — call when a model is loaded through
  /// `EngineService`, so [listInstalledModels]'s ordering reflects recency.
  /// Throws [StorageNotFoundFailure] if [id] isn't installed.
  Future<void> touchLastUsed(int id) async {
    final updated =
        await (_db.update(_db.installedModels)..where((t) => t.id.equals(id)))
            .write(InstalledModelsCompanion(lastUsedAt: Value(DateTime.now())));
    if (updated == 0) {
      throw StorageNotFoundFailure('no installed model with id $id');
    }
  }

  Future<int> totalUsageBytes() async {
    final rows = await listInstalledModels();
    var total = 0;
    for (final row in rows) {
      total += row.sizeBytes;
    }
    return total;
  }

  /// Deletes both the file on disk and the drift row. Throws
  /// [StorageNotFoundFailure] if [id] isn't installed, [StorageIoFailure] if
  /// the file exists but can't be deleted (row is left in place so the app
  /// doesn't lose track of an orphaned file).
  Future<void> delete(int id) async {
    final row = await (_db.select(
      _db.installedModels,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StorageNotFoundFailure('no installed model with id $id');
    }
    final file = File(row.localPath);
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      throw StorageIoFailure('failed to delete ${row.localPath}', cause: e);
    }
    await (_db.delete(_db.installedModels)..where((t) => t.id.equals(id))).go();
  }

  /// Guard before enqueueing a download/import of [requiredBytes]. Throws
  /// [StorageInsufficientSpaceFailure] when there isn't enough free space
  /// (200MB safety margin — see `download_core.checkStorageGuard`).
  Future<void> guardFreeSpace(int requiredBytes) async {
    final storage = await _deviceInfo.getStorageInfo();
    final failure = checkStorageGuard(
      requiredBytes: requiredBytes,
      freeBytes: storage.freeBytes,
    );
    if (failure != null) throw failure;
  }

  InstalledModelInfo _toInfo(InstalledModel row) => InstalledModelInfo(
    id: row.id,
    repoId: row.repoId,
    fileName: row.fileName,
    quant: row.quant,
    sizeBytes: row.sizeBytes,
    sha256: row.sha256,
    localPath: row.localPath,
    license: row.license,
    gated: row.gated,
    downloadedAt: row.downloadedAt,
    lastUsedAt: row.lastUsedAt,
  );
}
