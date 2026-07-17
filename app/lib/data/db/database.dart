import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// A GGUF model file the user has downloaded (via `DownloadManager`) or
/// imported locally (via `local_import.dart`) and that is ready to load
/// through `EngineService`. One row per installed file — a repo with three
/// installed quants is three rows.
///
/// Deviation from the T4 brief: no separate `download_tasks` table.
/// `background_downloader`'s own persistent SQLite task-tracking database
/// (activated via `FileDownloader().trackTasks()`, read back via
/// `FileDownloader().database.allRecords()`) survives app restarts and is
/// what `DownloadManager.init()` actually rehydrates in-flight/late-
/// completed tasks from — see `download_backend.dart`'s `rehydrate()` and
/// `download_manager.dart`'s `init()`/`DownloadRequest._encodeMetaData`.
/// Duplicating that tracking into drift would be two sources of truth for
/// the same in-flight bookkeeping. `installed_models` only gets a row once
/// a download/import completes and passes integrity checks — including a
/// completion that arrives after an app restart.
class InstalledModels extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get repoId => text()();
  TextColumn get fileName => text()();
  TextColumn get quant => text().nullable()();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text().nullable()();
  TextColumn get localPath => text()();
  TextColumn get license => text().nullable()();
  BoolColumn get gated => boolean().withDefault(const Constant(false))();
  DateTimeColumn get downloadedAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  // A given file within a repo is installed at most once.
  @override
  List<Set<Column>> get uniqueKeys => [
    {repoId, fileName},
  ];
}

@DriftDatabase(tables: [InstalledModels])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? _defaultExecutor());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _defaultExecutor() => driftDatabase(name: 'dhruva');

  /// Inserts [companion], or updates the existing row if one already exists
  /// for the same (repoId, fileName) pair.
  ///
  /// `insertOnConflictUpdate` alone is NOT enough here: drift's default
  /// conflict target is the primary key (`id`), which a fresh insert never
  /// collides with — the actual collision we care about is the table's
  /// `uniqueKeys` constraint (repoId + fileName), so the target has to be
  /// named explicitly or SQLite raises a raw `UNIQUE constraint failed`
  /// instead of upserting. Both `DownloadManager` and `local_import.dart`
  /// route through this one method so that fix lives in exactly one place.
  Future<int> upsertInstalledModel(InstalledModelsCompanion companion) {
    return into(installedModels).insert(
      companion,
      onConflict: DoUpdate(
        (_) => companion,
        target: [installedModels.repoId, installedModels.fileName],
      ),
    );
  }
}
