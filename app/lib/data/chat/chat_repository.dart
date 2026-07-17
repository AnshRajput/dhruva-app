import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/failures/app_failure.dart';
import '../db/database.dart';
import 'chat_export.dart';
import 'models/sampling_params.dart';

/// One `Folders` row, surfaced without the drift-generated type — see
/// `StorageManager`'s `InstalledModelInfo` for the precedent (ADR-002:
/// `features/` never imports drift directly).
final class FolderInfo {
  final int id;
  final String name;
  final int sortIndex;

  const FolderInfo({
    required this.id,
    required this.name,
    required this.sortIndex,
  });
}

/// One `Conversations` row.
final class ConversationSummary {
  final int id;
  final String title;
  final int? folderId;
  final int? modelId;

  /// The character (if any) this thread was started with — see
  /// `data/characters/character_repository.dart`'s `chatContextFor`. Null
  /// for an ordinary conversation, or once the character is deleted
  /// (`Conversations.characterId` FKs `onDelete: KeyAction.setNull`).
  final int? characterId;
  final String systemPrompt;
  final SamplingParams samplingParams;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;

  const ConversationSummary({
    required this.id,
    required this.title,
    this.folderId,
    this.modelId,
    this.characterId,
    required this.systemPrompt,
    required this.samplingParams,
    required this.createdAt,
    required this.updatedAt,
    required this.pinned,
  });
}

/// One `Messages` row.
final class MessageInfo {
  final int id;
  final int conversationId;
  final MessageRole role;
  final String content;
  final String? reasoningContent;
  final MessageStatus status;
  final String? errorKind;
  final int? tokCount;
  final int? genMs;
  final DateTime createdAt;
  final int? parentMessageId;

  const MessageInfo({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.reasoningContent,
    required this.status,
    this.errorKind,
    this.tokCount,
    this.genMs,
    required this.createdAt,
    this.parentMessageId,
  });
}

/// One [ChatRepository.search] hit.
final class ConversationSearchHit {
  final int conversationId;
  final String title;

  /// The matched message's content (trimmed around the match), or the
  /// conversation title itself when the title is what matched.
  final String snippet;

  const ConversationSearchHit({
    required this.conversationId,
    required this.title,
    required this.snippet,
  });
}

/// CRUD + search + export over the Loop-4 chat schema (`Folders`,
/// `Conversations`, `Messages` in `data/db/database.dart`).
///
/// Search is `LIKE '%term%'` on `conversations.title` and
/// `messages.content`, not FTS5. Drift 2.34.2 (the pinned version) has no
/// `Fts5Table` Dart DSL — the package's own FTS5 support is only exercised
/// via `.drift` schema files with generated typed queries (see the
/// package's `test/extensions/fts5_integration_test.dart`), which this
/// codebase's Dart-table-only schema doesn't use. Standing that up would
/// mean hand-written `CREATE VIRTUAL TABLE ... USING fts5` DDL plus
/// insert/update/delete triggers to keep the index in sync with `messages`
/// — real migration risk for a feature that, on a single-user on-device
/// chat history (tens to low thousands of rows, not millions), doesn't need
/// it. A `LIKE '%term%'` full scan of that row count is sub-millisecond.
/// One honest consequence: a leading-wildcard `LIKE` can't use a b-tree
/// index, so no index is added for search — one would just be dead weight
/// (see `database.dart`'s `idx_messages_conversation`, which exists for the
/// FK/`getMessages` hot path instead, where it actually helps).
final class ChatRepository {
  final AppDatabase _db;

  const ChatRepository({required AppDatabase db}) : _db = db;

  // ---- Folders ----------------------------------------------------------

  Future<int> createFolder(String name) {
    return _db.into(_db.folders).insert(FoldersCompanion.insert(name: name));
  }

  Future<void> renameFolder(int id, String name) async {
    final updated =
        await (_db.update(_db.folders)..where((t) => t.id.equals(id))).write(
          FoldersCompanion(name: Value(name)),
        );
    if (updated == 0) {
      throw StorageNotFoundFailure('no folder with id $id');
    }
  }

  /// Deletes the folder. Its conversations are un-filed (`folderId` set
  /// null), not deleted — enforced by the FK's `onDelete: KeyAction.
  /// setNull`, see `database.dart`.
  Future<void> deleteFolder(int id) async {
    final deleted = await (_db.delete(
      _db.folders,
    )..where((t) => t.id.equals(id))).go();
    if (deleted == 0) {
      throw StorageNotFoundFailure('no folder with id $id');
    }
  }

  Future<List<FolderInfo>> listFolders() async {
    final rows = await (_db.select(
      _db.folders,
    )..orderBy([(t) => OrderingTerm.asc(t.sortIndex)])).get();
    return rows
        .map((r) => FolderInfo(id: r.id, name: r.name, sortIndex: r.sortIndex))
        .toList(growable: false);
  }

  // ---- Conversations ------------------------------------------------------

  Future<int> createConversation({
    String title = '',
    int? folderId,
    int? modelId,
    int? characterId,
    String systemPrompt = '',
    SamplingParams? samplingParams,
  }) {
    samplingParams?.validate();
    final now = DateTime.now();
    return _db
        .into(_db.conversations)
        .insert(
          ConversationsCompanion.insert(
            title: Value(title),
            folderId: Value(folderId),
            modelId: Value(modelId),
            characterId: Value(characterId),
            systemPrompt: Value(systemPrompt),
            samplingParamsJson: Value(
              samplingParams == null
                  ? null
                  : jsonEncode(samplingParams.toJson()),
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> deleteConversation(int id) async {
    final deleted = await (_db.delete(
      _db.conversations,
    )..where((t) => t.id.equals(id))).go();
    if (deleted == 0) {
      throw StorageNotFoundFailure('no conversation with id $id');
    }
  }

  Future<void> renameConversation(int id, String title) {
    return _touchAndUpdate(id, ConversationsCompanion(title: Value(title)));
  }

  Future<void> setPinned(int id, bool pinned) {
    return _touchAndUpdate(id, ConversationsCompanion(pinned: Value(pinned)));
  }

  /// Pass `null` to un-file (move to no folder).
  Future<void> moveToFolder(int id, int? folderId) {
    return _touchAndUpdate(
      id,
      ConversationsCompanion(folderId: Value(folderId)),
    );
  }

  Future<void> setModel(int id, int? modelId) {
    return _touchAndUpdate(id, ConversationsCompanion(modelId: Value(modelId)));
  }

  Future<void> setSystemPrompt(int id, String systemPrompt) {
    return _touchAndUpdate(
      id,
      ConversationsCompanion(systemPrompt: Value(systemPrompt)),
    );
  }

  Future<void> setSamplingParams(int id, SamplingParams params) {
    params.validate();
    return _touchAndUpdate(
      id,
      ConversationsCompanion(
        samplingParamsJson: Value(jsonEncode(params.toJson())),
      ),
    );
  }

  Future<ConversationSummary?> getConversation(int id) async {
    final row = await (_db.select(
      _db.conversations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toSummary(row);
  }

  /// Pinned conversations first, then most-recently-updated first.
  /// Pass [folderId] to scope to one folder, or [onlyUnfiled] for
  /// conversations with no folder. Omit both for every conversation.
  Future<List<ConversationSummary>> listConversations({
    int? folderId,
    bool onlyUnfiled = false,
  }) async {
    final query = _db.select(_db.conversations);
    if (onlyUnfiled) {
      query.where((t) => t.folderId.isNull());
    } else if (folderId != null) {
      query.where((t) => t.folderId.equals(folderId));
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    final rows = await query.get();
    return rows.map(_toSummary).toList(growable: false);
  }

  /// Sets [conversationId]'s title to the first ~40 chars of its first user
  /// message. No-op if the title is already non-empty, or there's no user
  /// message yet. Called automatically by [appendMessage] on the first user
  /// message of a conversation — also exposed directly so callers (or
  /// tests) can trigger it idempotently.
  Future<void> renameAuto(int conversationId) async {
    final convo = await getConversation(conversationId);
    if (convo == null || convo.title.isNotEmpty) return;
    final firstUserMessage =
        await (_db.select(_db.messages)
              ..where(
                (t) =>
                    t.conversationId.equals(conversationId) &
                    t.role.equalsValue(MessageRole.user),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (firstUserMessage == null) return;
    final trimmed = firstUserMessage.content.trim();
    if (trimmed.isEmpty) return;
    final title = trimmed.length <= 40
        ? trimmed
        : '${trimmed.substring(0, 40)}…';
    await renameConversation(conversationId, title);
  }

  // ---- Messages -----------------------------------------------------------

  /// Inserts a new message and bumps the parent conversation's `updatedAt`.
  /// Triggers [renameAuto] when [role] is [MessageRole.user] (a no-op past
  /// the first user message, since `renameAuto` only fires on an empty
  /// title).
  Future<int> appendMessage({
    required int conversationId,
    required MessageRole role,
    String content = '',
    String? reasoningContent,
    MessageStatus status = MessageStatus.complete,
    String? errorKind,
    int? tokCount,
    int? genMs,
    int? parentMessageId,
  }) async {
    final id = await _db
        .into(_db.messages)
        .insert(
          MessagesCompanion.insert(
            conversationId: conversationId,
            role: role,
            content: Value(content),
            reasoningContent: Value(reasoningContent),
            status: status,
            errorKind: Value(errorKind),
            tokCount: Value(tokCount),
            genMs: Value(genMs),
            createdAt: DateTime.now(),
            parentMessageId: Value(parentMessageId),
          ),
        );
    await _touchUpdatedAt(conversationId);
    if (role == MessageRole.user) {
      await renameAuto(conversationId);
    }
    return id;
  }

  /// Appends [contentDelta]/[reasoningDelta] to a streaming message's
  /// existing content, as a single `content = content || ?` SQL statement —
  /// not a Dart-side read-modify-write. This is deliberately NOT
  /// timer-batched: a real llama.cpp decode on-device tops out around
  /// 50-100 tok/s, i.e. at most ~100 single-row scalar `UPDATE`s/sec, and
  /// `updateStreamingMessage`'s own test times 200 back-to-back calls
  /// against an in-memory db in well under a millisecond each — a
  /// batching/flush timer (with its own cancel-on-finalize and
  /// dispose-race edge cases) would be solving a problem that isn't there.
  /// If a slower device profile ever shows scroll jank traceable to this,
  /// the upgrade path is a caller-side throttle (flush every ~80ms),
  /// not a rewrite of this method.
  Future<void> updateStreamingMessage(
    int messageId, {
    String? contentDelta,
    String? reasoningDelta,
  }) async {
    final hasContent = contentDelta != null && contentDelta.isNotEmpty;
    final hasReasoning = reasoningDelta != null && reasoningDelta.isNotEmpty;
    if (!hasContent && !hasReasoning) return;

    final sets = <String>[];
    final vars = <Variable<Object>>[];
    if (hasContent) {
      sets.add('content = content || ?${vars.length + 1}');
      vars.add(Variable<String>(contentDelta));
    }
    if (hasReasoning) {
      sets.add(
        "reasoning_content = COALESCE(reasoning_content, '') || ?${vars.length + 1}",
      );
      vars.add(Variable<String>(reasoningDelta));
    }
    vars.add(Variable<int>(messageId));
    await _db.customUpdate(
      'UPDATE messages SET ${sets.join(', ')} WHERE id = ?${vars.length}',
      variables: vars,
      updates: {_db.messages},
    );
  }

  /// Absolute overwrite of a streaming message's `content`/
  /// `reasoningContent` — the rare counterpart to [updateStreamingMessage]'s
  /// append-only path (staff review N1). `ChatController._flush` reaches
  /// for this only when a re-derived `<think>` split ISN'T a genuine
  /// extension of what was already pushed (e.g. tag-stripping shrinking
  /// `content` mid-stream) — appending a delta in that case would silently
  /// diverge the row from the true in-memory text, so a full rewrite beats
  /// that. [reasoningContent] null clears the column (unlike the append
  /// path's `COALESCE`, this call is meant to make the row match the
  /// caller's state exactly, not preserve whatever was there before).
  Future<void> setStreamingContent(
    int messageId, {
    required String content,
    String? reasoningContent,
  }) async {
    await (_db.update(
      _db.messages,
    )..where((t) => t.id.equals(messageId))).write(
      MessagesCompanion(
        content: Value(content),
        reasoningContent: Value(reasoningContent),
      ),
    );
  }

  /// Sets a message's terminal [status]/stats once generation stops, and
  /// bumps the parent conversation's `updatedAt` to reflect completion time
  /// (not just when the message started streaming).
  Future<void> finalize(
    int messageId, {
    required MessageStatus status,
    String? errorKind,
    int? tokCount,
    int? genMs,
  }) async {
    final message = await (_db.select(
      _db.messages,
    )..where((t) => t.id.equals(messageId))).getSingleOrNull();
    if (message == null) {
      throw StorageNotFoundFailure('no message with id $messageId');
    }
    await (_db.update(
      _db.messages,
    )..where((t) => t.id.equals(messageId))).write(
      MessagesCompanion(
        status: Value(status),
        errorKind: Value(errorKind),
        tokCount: Value(tokCount),
        genMs: Value(genMs),
      ),
    );
    await _touchUpdatedAt(message.conversationId);
  }

  /// Ordered oldest-first (then by id, to break same-millisecond ties
  /// deterministically).
  Future<List<MessageInfo>> getMessages(int conversationId) async {
    final rows =
        await (_db.select(_db.messages)
              ..where((t) => t.conversationId.equals(conversationId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return rows.map(_toMessageInfo).toList(growable: false);
  }

  /// Deletes every conversation — and, via the `Messages.conversationId`
  /// FK's `onDelete: KeyAction.cascade` (SQLite-enforced, see
  /// `database.dart`), every message with it. Installed models and
  /// downloaded files are untouched — this is the Settings screen's "Clear
  /// all chat history" action (Amendment 4b), and that boundary is exactly
  /// what its confirmation copy promises.
  Future<void> clearAllHistory() => _db.delete(_db.conversations).go();

  // ---- Search ---------------------------------------------------------

  /// See the class doc for why this is `LIKE`, not FTS5.
  Future<List<ConversationSearchHit>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final pattern = '%${_escapeLike(trimmed)}%';

    final joined =
        _db.select(_db.conversations).join([
            leftOuterJoin(
              _db.messages,
              _db.messages.conversationId.equalsExp(_db.conversations.id) &
                  _db.messages.content.like(pattern, escapeChar: r'\'),
            ),
          ])
          ..where(
            _db.conversations.title.like(pattern, escapeChar: r'\') |
                _db.messages.content.like(pattern, escapeChar: r'\'),
          )
          ..orderBy([OrderingTerm.desc(_db.conversations.updatedAt)]);

    final rows = await joined.get();
    final seenConversations = <int>{};
    final hits = <ConversationSearchHit>[];
    for (final row in rows) {
      final convo = row.readTable(_db.conversations);
      if (!seenConversations.add(convo.id)) continue;
      final message = row.readTableOrNull(_db.messages);
      final snippet = message != null && message.content.contains(trimmed)
          ? _snippet(message.content, trimmed)
          : convo.title;
      hits.add(
        ConversationSearchHit(
          conversationId: convo.id,
          title: convo.title,
          snippet: snippet,
        ),
      );
    }
    return hits;
  }

  static String _escapeLike(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static const _snippetContext = 30;

  static String _snippet(String content, String query) {
    final index = content.toLowerCase().indexOf(query.toLowerCase());
    if (index < 0) return content;
    final start = (index - _snippetContext).clamp(0, content.length);
    final end = (index + query.length + _snippetContext).clamp(
      0,
      content.length,
    );
    final prefix = start > 0 ? '…' : '';
    final suffix = end < content.length ? '…' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }

  // ---- Export -----------------------------------------------------------

  Future<ChatExportData> _exportData(int conversationId) async {
    final convo = await getConversation(conversationId);
    if (convo == null) {
      throw StorageNotFoundFailure('no conversation with id $conversationId');
    }
    final messages = await getMessages(conversationId);
    final modelLabel = await _modelLabel(convo.modelId);
    return ChatExportData(
      title: convo.title.isEmpty ? 'Untitled conversation' : convo.title,
      modelLabel: modelLabel,
      createdAt: convo.createdAt,
      messages: messages,
    );
  }

  Future<String> exportConversationMarkdown(int conversationId) async {
    return formatConversationMarkdown(await _exportData(conversationId));
  }

  Future<String> exportConversationJson(int conversationId) async {
    return formatConversationJson(await _exportData(conversationId));
  }

  Future<String?> _modelLabel(int? modelId) async {
    if (modelId == null) return null;
    final row = await (_db.select(
      _db.installedModels,
    )..where((t) => t.id.equals(modelId))).getSingleOrNull();
    if (row == null) return null;
    return row.quant == null ? row.repoId : '${row.repoId} (${row.quant})';
  }

  // ---- shared helpers -----------------------------------------------------

  Future<void> _touchAndUpdate(int id, ConversationsCompanion patch) async {
    final updated = await (_db.update(
      _db.conversations,
    )..where((t) => t.id.equals(id))).write(patch);
    if (updated == 0) {
      throw StorageNotFoundFailure('no conversation with id $id');
    }
    await _touchUpdatedAt(id);
  }

  Future<void> _touchUpdatedAt(int conversationId) {
    return (_db.update(_db.conversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsCompanion(updatedAt: Value(DateTime.now())));
  }

  ConversationSummary _toSummary(Conversation row) => ConversationSummary(
    id: row.id,
    title: row.title,
    folderId: row.folderId,
    modelId: row.modelId,
    characterId: row.characterId,
    systemPrompt: row.systemPrompt,
    samplingParams: row.samplingParamsJson == null
        ? const SamplingParams()
        : SamplingParams.fromJson(
            jsonDecode(row.samplingParamsJson!) as Map<String, dynamic>,
          ),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    pinned: row.pinned,
  );

  MessageInfo _toMessageInfo(Message row) => MessageInfo(
    id: row.id,
    conversationId: row.conversationId,
    role: row.role,
    content: row.content,
    reasoningContent: row.reasoningContent,
    status: row.status,
    errorKind: row.errorKind,
    tokCount: row.tokCount,
    genMs: row.genMs,
    createdAt: row.createdAt,
    parentMessageId: row.parentMessageId,
  );
}
