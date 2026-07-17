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

/// A user-created group of conversations (Loop-4 chat sidebar). Deleting a
/// folder un-files its conversations (`Conversations.folderId` FKs here with
/// `onDelete: KeyAction.setNull`) rather than deleting them.
class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();
}

/// Role of a `Messages` row. Stored as an int via `intEnum` (index-based),
/// so reordering these values is a breaking schema change.
enum MessageRole { user, assistant, system }

/// Terminal state of a `Messages` row once generation stops.
enum MessageStatus { complete, cancelled, error }

/// A chat thread.
///
/// `modelId` is FK'd to `InstalledModels.id` with `onDelete: KeyAction.
/// setNull`: deleting an installed model un-sets `modelId` on any
/// conversation that used it (DB-enforced, not app code) rather than
/// deleting the conversation or blocking the delete — "survives model
/// deletion" per the Loop-4 brief. `ChatRepository` treats a null/dangling
/// `modelId` as "model no longer installed" and degrades gracefully (export
/// shows no model line, UI would show a picker instead of a name).
class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get folderId => integer().nullable().references(
    Folders,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get modelId => integer().nullable().references(
    InstalledModels,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get systemPrompt => text().withDefault(const Constant(''))();

  /// `SamplingParams.toJson()` (see `data/chat/models/sampling_params.dart`),
  /// or null to use `SamplingParams()` defaults.
  TextColumn get samplingParamsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
}

/// One chat message. `conversationId` cascades on delete — deleting a
/// conversation deletes its messages, enforced by SQLite, not a
/// repository-side loop.
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId =>
      integer().references(Conversations, #id, onDelete: KeyAction.cascade)();
  IntColumn get role => intEnum<MessageRole>()();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// Extracted `<think>...</think>` text, kept separate from `content` so
  /// the UI can collapse it independently.
  TextColumn get reasoningContent => text().nullable()();
  IntColumn get status => intEnum<MessageStatus>()();

  /// Free-text failure-kind label (e.g. an `EngineFailure`/`AppFailure`
  /// `runtimeType`). This layer deliberately doesn't depend on
  /// `engine_bindings`'s failure tree (ADR-002 dependency direction) — it
  /// just stores whatever label the caller passed.
  TextColumn get errorKind => text().nullable()();
  IntColumn get tokCount => integer().nullable()();
  IntColumn get genMs => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// Enables edit/regenerate history (a regenerated or edited message
  /// points back at the message it replaced) without a full tree UI — this
  /// is linear-history provenance, not a real tree; a deleted parent just
  /// un-sets the pointer.
  IntColumn get parentMessageId => integer().nullable().references(
    Messages,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

@DriftDatabase(tables: [InstalledModels, Folders, Conversations, Messages])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? _defaultExecutor());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createMessagesConversationIndex();
    },
    onUpgrade: (m, from, to) async {
      // v1 -> v2 (Loop 4): chat data layer. installed_models is untouched.
      if (from < 2) {
        await m.createTable(folders);
        await m.createTable(conversations);
        await m.createTable(messages);
        await _createMessagesConversationIndex();
      }
    },
    beforeOpen: (details) async {
      // SQLite foreign keys are opt-in per connection — required for the
      // onDelete: setNull/cascade behavior declared above to actually fire.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // Raw SQL rather than a `@TableIndex` annotation: keeps the create-table
  // and create-index steps symmetric across `onCreate`/`onUpgrade` without
  // guessing drift_dev's generated accessor name for an annotated index.
  Future<void> _createMessagesConversationIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS idx_messages_conversation '
    'ON messages (conversation_id)',
  );

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
