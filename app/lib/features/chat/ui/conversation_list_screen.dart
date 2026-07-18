/// Conversation list (chat-spec.md §6.2) — the app's `/chat` home tab.
/// Pinned-first ordering straight from `ChatRepository.listConversations`,
/// folder chip filter, debounced search, swipe/menu actions, FAB new-chat
/// flow (model picker if multiple installed / auto if one / models-hub CTA
/// if none).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../data/chat/chat_repository.dart';
import '../state/chat_controller.dart' show ChatRouteArgs;
import '../state/conversation_list_controller.dart';
import '../state/installed_models_provider.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/empty_states.dart';
import 'model_picker_sheet.dart';
import 'voice_launch.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() =>
      _ConversationListScreenState();
}

class _ConversationListScreenState
    extends ConsumerState<ConversationListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // chat-spec.md §6.2: "debounced 300ms (motion.moderate-adjacent but
    // this is a debounce not an animation — reuse the number, don't invent
    // a new one)" — a literal here, per that note, not a token lookup.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(conversationListControllerProvider.notifier).search(value);
    });
  }

  Future<void> _startNewChat() async {
    final models = await ref.read(installedModelsProvider.future);
    if (models.isEmpty) {
      // UX-hardening A4: don't silently bounce to /models — tell the user why
      // first, then route with intent.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download a model to start chatting.')),
      );
      unawaited(context.push('/models'));
      return;
    }
    int modelId;
    if (models.length == 1) {
      modelId = models.single.id;
    } else {
      if (!mounted) return;
      final picked = await showModelPickerSheet(context);
      if (picked == null) return;
      modelId = picked.id;
    }
    if (mounted) unawaited(context.push('/chat/new', extra: modelId));
  }

  /// WS5 "obvious entry point": the always-visible, text-labelled voice launch
  /// on the app's home. Picks a model the same way [_startNewChat] does (so it
  /// never dead-ends), then opens hands-free against a fresh chat — a
  /// first-time user finds voice here without decoding an app-bar glyph.
  /// Doesn't hide when no model is installed; it guides to the models hub.
  Future<void> _startVoice() async {
    final models = await ref.read(installedModelsProvider.future);
    if (!mounted) return;
    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download a model to talk hands-free.')),
      );
      unawaited(context.push('/models'));
      return;
    }
    int modelId;
    if (models.length == 1) {
      modelId = models.single.id;
    } else {
      final picked = await showModelPickerSheet(context);
      if (picked == null) return;
      modelId = picked.id;
    }
    if (!mounted) return;
    await openHandsFreeVoice(
      context,
      ref,
      ChatRouteArgs(initialModelId: modelId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final state = ref.watch(conversationListControllerProvider);
    final modelsAsync = ref.watch(installedModelsProvider);
    // UX-hardening A4: default false while loading so the honest "No model
    // installed → Browse models" empty state shows on a fresh install, instead
    // of a "New chat" CTA whose FAB immediately bounces to /models.
    final hasAnyModel = modelsAsync.value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          // WS5: a labelled, always-present voice entry — not an unlabelled
          // waveform glyph. Visible on every state of the home (empty or full),
          // so voice is findable before any conversation exists.
          TextButton.icon(
            onPressed: _startVoice,
            icon: const Icon(Icons.record_voice_over_outlined, size: 18),
            label: const Text('Talk'),
          ),
          SizedBox(width: tokens.spacing.xs),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.md,
              tokens.spacing.sm,
              tokens.spacing.md,
              0,
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search conversations',
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: switch (state) {
              AsyncData(:final value) =>
                value.isSearching
                    ? _SearchResults(hits: value.searchResults)
                    : _ConversationBody(
                        state: value,
                        hasAnyModel: hasAnyModel,
                        onNewChat: _startNewChat,
                      ),
              AsyncError(:final error) => ErrorStateView(
                error: error,
                onRetry: () =>
                    ref.invalidate(conversationListControllerProvider),
              ),
              _ => const Center(child: DhruvaLoader()),
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ConversationBody extends ConsumerWidget {
  final ConversationListState state;
  final bool hasAnyModel;
  final VoidCallback onNewChat;

  const _ConversationBody({
    required this.state,
    required this.hasAnyModel,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(conversationListControllerProvider.notifier).refresh(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.md,
                vertical: tokens.spacing.xs,
              ),
              children: [
                _FolderChip(
                  label: 'All',
                  selected: state.selectedFolderId == null,
                  onTap: () => ref
                      .read(conversationListControllerProvider.notifier)
                      .selectFolder(null),
                ),
                for (final folder in state.folders) ...[
                  SizedBox(width: tokens.spacing.xs),
                  _FolderChip(
                    label: folder.name,
                    selected: state.selectedFolderId == folder.id,
                    onTap: () => ref
                        .read(conversationListControllerProvider.notifier)
                        .selectFolder(folder.id),
                  ),
                ],
                SizedBox(width: tokens.spacing.xs),
                ActionChip(
                  label: const Icon(Icons.add, size: 16),
                  onPressed: () => _createFolder(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.conversations.isEmpty
                ? (hasAnyModel
                      ? NoConversationsView(onNewChat: onNewChat)
                      : NoModelInstalledView(
                          onBrowseModels: () => context.push('/models'),
                        ))
                : ListView.builder(
                    itemCount: state.conversations.length,
                    itemBuilder: (context, i) => ConversationTile(
                      conversation: state.conversations[i],
                      folders: state.folders,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref
          .read(conversationListControllerProvider.notifier)
          .createFolder(name);
    }
  }
}

class _FolderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FolderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<ConversationSearchHit> hits;
  const _SearchResults({required this.hits});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (hits.isEmpty) {
      return const Center(child: Text('No conversations match your search.'));
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final hit = hits[i];
        return ListTile(
          title: Text(
            hit.title.isEmpty ? 'Untitled conversation' : hit.title,
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(
            hit.snippet,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => context.push('/chat/${hit.conversationId}'),
        );
      },
    );
  }
}
