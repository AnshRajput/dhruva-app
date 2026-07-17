import 'dart:io';

import 'package:drift/drift.dart';

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

  /// Local path of the paired mmproj projector, or null — see
  /// `database.dart`'s `InstalledModels.mmprojPath` doc for the "needs
  /// projector" half-state `isVision && mmprojPath == null` represents.
  final String? mmprojPath;
  final bool isVision;

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
    this.mmprojPath,
    this.isVision = false,
  });

  /// True when this is a vision model whose projector download hasn't
  /// completed yet — the model itself is installed and usable text-only.
  bool get needsProjector => isVision && mmprojPath == null;
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

  /// Sums every installed model's own file size plus, for a vision model
  /// whose projector has landed, the projector file's size too (D5: "total
  /// usage counts both"). The projector's size isn't a stored column (only
  /// its path is — see `database.dart`'s `InstalledModels.mmprojPath`), so
  /// it's `stat`'d off disk here rather than adding a third schema column
  /// for a value the filesystem already knows.
  Future<int> totalUsageBytes() async {
    final rows = await listInstalledModels();
    var total = 0;
    for (final row in rows) {
      total += row.sizeBytes;
      final mmprojPath = row.mmprojPath;
      if (mmprojPath != null) {
        final mmprojFile = File(mmprojPath);
        if (mmprojFile.existsSync()) total += mmprojFile.lengthSync();
      }
    }
    return total;
  }

  /// Deletes the file on disk (plus its mmproj projector, if this is a
  /// vision model with one — D5) and the drift row. Throws
  /// [StorageNotFoundFailure] if [id] isn't installed, [StorageIoFailure] if
  /// a file exists but can't be deleted (row is left in place so the app
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
    final mmprojPath = row.mmprojPath;
    if (mmprojPath != null) {
      final mmprojFile = File(mmprojPath);
      try {
        if (mmprojFile.existsSync()) await mmprojFile.delete();
      } on FileSystemException catch (e) {
        throw StorageIoFailure('failed to delete $mmprojPath', cause: e);
      }
    }
    await (_db.delete(_db.installedModels)..where((t) => t.id.equals(id))).go();
  }

  /// Records where a vision model's mmproj projector landed once its own
  /// (separately enqueued, sequential) download completes — the second half
  /// of a vision pairing; see `download_actions_controller.dart`'s
  /// `enqueueVisionQuant`. Throws [StorageNotFoundFailure] if no installed
  /// model matches (repoId, fileName) — the projector download is only ever
  /// started after the model's own row is written, so this should never
  /// actually be reached; kept as a typed guard rather than a silent no-op.
  Future<void> attachProjector({
    required String repoId,
    required String fileName,
    required String mmprojPath,
  }) async {
    final updated =
        await (_db.update(_db.installedModels)..where(
              (t) => t.repoId.equals(repoId) & t.fileName.equals(fileName),
            ))
            .write(
              InstalledModelsCompanion(
                mmprojPath: Value(mmprojPath),
                isVision: const Value(true),
              ),
            );
    if (updated == 0) {
      throw StorageNotFoundFailure(
        'no installed model $repoId/$fileName to attach a projector to',
      );
    }
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
    mmprojPath: row.mmprojPath,
    isVision: row.isVision,
  );
}
