/// Conversation-list screen state (chat-spec.md §6.2): pinned-first
/// ordering straight from `ChatRepository.listConversations` (no client
/// re-sort), folder filter, and search (which overrides the folder filter
/// while a query is active — `ChatRepository.search` isn't folder-scoped).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/chat/chat_repository.dart';

final class ConversationListState {
  final List<FolderInfo> folders;

  /// Null = "All" chip.
  final int? selectedFolderId;
  final List<ConversationSummary> conversations;
  final String query;
  final List<ConversationSearchHit> searchResults;
  final AppFailure? actionError;

  const ConversationListState({
    this.folders = const [],
    this.selectedFolderId,
    this.conversations = const [],
    this.query = '',
    this.searchResults = const [],
    this.actionError,
  });

  bool get isSearching => query.isNotEmpty;

  ConversationListState copyWith({
    List<FolderInfo>? folders,
    int? selectedFolderId,
    bool clearSelectedFolderId = false,
    List<ConversationSummary>? conversations,
    String? query,
    List<ConversationSearchHit>? searchResults,
    AppFailure? actionError,
    bool clearActionError = false,
  }) {
    return ConversationListState(
      folders: folders ?? this.folders,
      selectedFolderId: clearSelectedFolderId
          ? null
          : (selectedFolderId ?? this.selectedFolderId),
      conversations: conversations ?? this.conversations,
      query: query ?? this.query,
      searchResults: searchResults ?? this.searchResults,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }
}

final conversationListControllerProvider =
    AsyncNotifierProvider<ConversationListController, ConversationListState>(
      ConversationListController.new,
    );

class ConversationListController extends AsyncNotifier<ConversationListState> {
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  Future<ConversationListState> build() async {
    // UX-hardening A2: refresh (preserving folder/search filter) when a
    // conversation is created or cleared from outside this controller
    // (`ChatController` lazy-create, settings clear-all) — see
    // `conversationListRevisionProvider`.
    ref.listen(conversationListRevisionProvider, (_, _) {
      unawaited(refresh());
    });
    final folders = await _repo.listFolders();
    final conversations = await _repo.listConversations();
    return ConversationListState(
      folders: folders,
      conversations: conversations,
    );
  }

  Future<void> refresh() async {
    final current = state.value;
    final folders = await _repo.listFolders();
    final conversations = await _repo.listConversations(
      folderId: current?.selectedFolderId,
    );
    state = AsyncData(
      (current ?? const ConversationListState()).copyWith(
        folders: folders,
        conversations: _withoutPending(conversations),
      ),
    );
  }

  Future<void> selectFolder(int? folderId) async {
    final current = state.value;
    if (current == null) return;
    final conversations = await _repo.listConversations(folderId: folderId);
    state = AsyncData(
      current.copyWith(
        selectedFolderId: folderId,
        clearSelectedFolderId: folderId == null,
        conversations: _withoutPending(conversations),
      ),
    );
  }

  Future<void> search(String query) async {
    final current = state.value;
    if (current == null) return;
    final trimmed = query.trim();
    final results = trimmed.isEmpty
        ? <ConversationSearchHit>[]
        : await _repo.search(trimmed);
    state = AsyncData(current.copyWith(query: trimmed, searchResults: results));
  }

  Future<void> createFolder(String name) async {
    await _repo.createFolder(name);
    await refresh();
  }

  Future<void> setPinned(int conversationId, bool pinned) async {
    await _guarded(() => _repo.setPinned(conversationId, pinned));
  }

  Future<void> rename(int conversationId, String title) async {
    await _guarded(() => _repo.renameConversation(conversationId, title));
  }

  Future<void> moveToFolder(int conversationId, int? folderId) async {
    await _guarded(() => _repo.moveToFolder(conversationId, folderId));
  }

  Future<void> delete(int conversationId) async {
    await _guarded(() => _repo.deleteConversation(conversationId));
  }

  // Deletes held back for the Undo window (conversation id -> commit timer).
  final Map<int, Timer> _pendingDeletes = {};

  /// Hides the row now and deletes it after [window] unless [undoDelete] is
  /// called first (swipe-to-delete with an Undo snackbar instead of a confirm
  /// dialog over a half-swiped row). If the app dies inside the window the
  /// conversation is simply still there: the safe failure.
  void deleteWithUndo(
    int conversationId, {
    Duration window = const Duration(seconds: 4),
  }) {
    final current = state.value;
    if (current == null) return;
    _pendingDeletes[conversationId]?.cancel();
    _pendingDeletes[conversationId] = Timer(window, () {
      _pendingDeletes.remove(conversationId);
      unawaited(delete(conversationId));
    });
    state = AsyncData(
      current.copyWith(
        conversations: [
          for (final c in current.conversations)
            if (c.id != conversationId) c,
        ],
      ),
    );
  }

  /// Cancels a held delete and brings the row back.
  void undoDelete(int conversationId) {
    final timer = _pendingDeletes.remove(conversationId);
    if (timer == null) return;
    timer.cancel();
    unawaited(refresh());
  }

  List<ConversationSummary> _withoutPending(List<ConversationSummary> all) =>
      _pendingDeletes.isEmpty
      ? all
      : [
          for (final c in all)
            if (!_pendingDeletes.containsKey(c.id)) c,
        ];

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
    } on AppFailure catch (e) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWith(actionError: e));
      }
    }
  }
}
