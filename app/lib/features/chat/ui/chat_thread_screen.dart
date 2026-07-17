/// Chat thread screen (chat-spec.md §1-4, §7-8) — the `/chat/:id` route.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/chat/chat_repository.dart';
import '../state/character_info_provider.dart';
import '../state/chat_controller.dart';
import '../state/message_info_x.dart';
import '../widgets/brand_motif.dart';
import '../widgets/chat_error.dart';
import '../widgets/composer.dart';
import '../widgets/empty_states.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_chip.dart';
import 'model_picker_sheet.dart';
import 'sampling_settings_sheet.dart';

class ChatThreadScreen extends ConsumerStatefulWidget {
  final ChatRouteArgs args;
  const ChatThreadScreen({super.key, required this.args});

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _scrollCtrl = ScrollController();
  var _pinnedToBottom = true;
  var _requestedLoad = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final distanceFromBottom =
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels;
    final pinned = distanceFromBottom <= _scrollCtrl.position.viewportDimension;
    if (pinned != _pinnedToBottom) setState(() => _pinnedToBottom = pinned);
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    setState(() => _pinnedToBottom = true);
  }

  void _maybeAutoScroll() {
    if (!_pinnedToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = chatControllerProvider(widget.args);
    final asyncState = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    ref.listen(provider, (previous, next) {
      final prevLen = previous?.value?.messages.length ?? 0;
      final nextLen = next.value?.messages.length ?? 0;
      if (nextLen != prevLen || (next.value?.isGenerating ?? false)) {
        _maybeAutoScroll();
      }
    });

    return asyncState.when(
      data: (state) {
        if (!_requestedLoad && state.modelId != null) {
          _requestedLoad = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => controller.ensureModelLoaded(),
          );
        }
        return _ThreadScaffold(
          args: widget.args,
          state: state,
          controller: controller,
          scrollCtrl: _scrollCtrl,
          pinnedToBottom: _pinnedToBottom,
          onScrollToBottom: _scrollToBottom,
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => const Scaffold(
        body: Center(child: Text('Could not open this conversation.')),
      ),
    );
  }
}

class _ThreadScaffold extends ConsumerWidget {
  final ChatRouteArgs args;
  final ChatThreadState state;
  final ChatController controller;
  final ScrollController scrollCtrl;
  final bool pinnedToBottom;
  final VoidCallback onScrollToBottom;

  const _ThreadScaffold({
    required this.args,
    required this.state,
    required this.controller,
    required this.scrollCtrl,
    required this.pinnedToBottom,
    required this.onScrollToBottom,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final visible = state.visibleMessages;

    return Scaffold(
      appBar: AppBar(
        // Loop 5: alongside, not instead of — the model chip is still how
        // a character-bound conversation with no default model gets one
        // (its "Pick a model" affordance from chat-spec.md §1.1 is what
        // gates the composer being visible at all, see the `Composer`
        // conditional below), so a character identity strip sits beside it
        // rather than displacing it.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.characterId != null) ...[
              _CharacterAppBarTitle(characterId: state.characterId!),
              SizedBox(width: tokens.spacing.xs),
            ],
            Flexible(
              child: ModelChip(
                model: state.model,
                onTap: () => _pickModel(context),
              ),
            ),
          ],
        ),
        titleSpacing: 0,
        actions: [
          if (state.isGenerating)
            TokPerSecTicker(tokPerSec: state.liveTokPerSec),
          PopupMenuButton<String>(
            onSelected: (value) => _export(context, ref, value == 'markdown'),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'markdown',
                child: Text('Export as Markdown'),
              ),
              PopupMenuItem(value: 'json', child: Text('Export as JSON')),
            ],
            enabled: state.conversationId != null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                visible.isEmpty &&
                    !state.isGenerating &&
                    state.modelLoadError == null
                ? Center(
                    child: state.model == null
                        ? NoModelInstalledView(
                            onBrowseModels: () => context.push('/models'),
                          )
                        : Padding(
                            padding: EdgeInsets.all(tokens.spacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DhruvaStar(
                                  size: 72,
                                  color: theme.colorScheme.primary,
                                ),
                                SizedBox(height: tokens.spacing.md),
                                Text(
                                  'Say hello',
                                  style: theme.textTheme.headlineSmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: scrollCtrl,
                        padding: EdgeInsets.all(tokens.spacing.md),
                        itemCount:
                            visible.length +
                            (state.awaitingFirstToken ? 1 : 0) +
                            (state.modelLoadError != null ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i < visible.length) {
                            final message = visible[i];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: tokens.spacing.xs,
                              ),
                              child: _buildMessageItem(context, ref, message),
                            );
                          }
                          var index = i - visible.length;
                          if (state.awaitingFirstToken) {
                            if (index == 0) {
                              return const Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: TypingIndicator(),
                                ),
                              );
                            }
                            index -= 1;
                          }
                          return ChatErrorCard(
                            content: chatErrorContentFor(
                              state.modelLoadError!.runtimeType.toString(),
                            ),
                            onAction: (action) =>
                                _handleModelLoadError(context, ref, action),
                          );
                        },
                      ),
                      // Nit 5: chat-spec.md §10 — pill appear/disappear is
                      // `motion.fast`/`motion.standard`, not a bare
                      // mount/unmount toggle. The Positioned itself stays
                      // mounted (Stack needs it for layout); AnimatedOpacity
                      // does the actual fade, IgnorePointer keeps the
                      // invisible button from eating taps while hidden.
                      Positioned(
                        bottom: tokens.spacing.md,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: IgnorePointer(
                            ignoring: pinnedToBottom,
                            child: AnimatedOpacity(
                              opacity: pinnedToBottom ? 0 : 1,
                              duration: tokens.motion.fast,
                              curve: tokens.motion.standard,
                              child: FilledButton.icon(
                                onPressed: onScrollToBottom,
                                icon: const Icon(
                                  Icons.arrow_downward,
                                  size: 16,
                                ),
                                label: const Text('New message'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (state.modelLoading) const LinearProgressIndicator(),
          // Designer BLOCKING #1: chat-spec.md §7.1 — "no composer visible
          // on this state" whenever there's no model to send to (fresh
          // draft with none picked yet, OR an existing conversation whose
          // model was uninstalled — `Conversations.modelId` FKs `setNull`
          // on delete, so this is reachable outside the brand-new-draft
          // case too). The AppBar's `ModelChip` still reads "Pick a model"
          // and opens the picker either way, so the user isn't stranded.
          if (state.model != null)
            Composer(
              isGenerating: state.isGenerating,
              onSend: (text) {
                onScrollToBottom();
                controller.sendMessage(text);
              },
              onCancel: controller.cancel,
              onOpenSettings: () => showSamplingSettingsSheet(context, args),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    WidgetRef ref,
    MessageInfo message,
  ) {
    if (message.role == MessageRole.assistant &&
        message.status == MessageStatus.error) {
      return ChatErrorCard(
        content: chatErrorContentFor(message.errorKind),
        onAction: (action) =>
            _handleMessageError(context, ref, message, action),
      );
    }
    final isStreamingMessage = message.id == state.streamingMessageId;
    if (isStreamingMessage &&
        message.content.isEmpty &&
        (message.reasoningContent ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    final canAct = !state.isGenerating;
    return MessageBubble(
      message: message,
      isStreaming: isStreamingMessage,
      reasoningDurationMs: state.reasoningDurationMs[message.id],
      reasoningOpen:
          isStreamingMessage &&
          !state.reasoningDurationMs.containsKey(message.id),
      onRegenerate: message.role == MessageRole.assistant && canAct
          ? () => controller.regenerate(message.id)
          : null,
      onEdit: message.role == MessageRole.user && canAct
          ? () => _editMessage(context, message)
          : null,
    );
  }

  Future<void> _editMessage(BuildContext context, MessageInfo message) async {
    final ctrl = TextEditingController(text: message.content);
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 6),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Save & resend'),
          ),
        ],
      ),
    );
    if (newText != null && newText.trim().isNotEmpty) {
      await controller.editMessage(message.id, newText);
    }
  }

  Future<void> _pickModel(BuildContext context) async {
    final picked = await showModelPickerSheet(
      context,
      selectedModelId: state.modelId,
    );
    if (picked != null) await controller.switchModel(picked);
  }

  Future<void> _handleMessageError(
    BuildContext context,
    WidgetRef ref,
    MessageInfo message,
    ChatRecoveryAction action,
  ) async {
    switch (action) {
      case ChatRecoveryAction.retry:
      case ChatRecoveryAction.retryAnyway:
        await controller.regenerate(message.id);
      case ChatRecoveryAction.smallerModel:
        final picked = await showModelPickerSheet(
          context,
          selectedModelId: state.modelId,
          smallerModelsOnly: true,
        );
        if (picked != null) {
          await controller.switchModel(picked);
          await controller.regenerate(message.id);
        }
      case ChatRecoveryAction.redownload:
        if (state.model != null && context.mounted) {
          unawaited(
            context.push(
              '/models/repo/${Uri.encodeComponent(state.model!.repoId)}',
            ),
          );
        }
      case ChatRecoveryAction.reloadModel:
        await controller.ensureModelLoaded();
        await controller.regenerate(message.id);
      case ChatRecoveryAction.copyDetails:
        if (context.mounted) {
          await copyErrorDetails(
            context,
            controller.errorDetailsFor(message.id),
          );
        }
    }
  }

  Future<void> _handleModelLoadError(
    BuildContext context,
    WidgetRef ref,
    ChatRecoveryAction action,
  ) async {
    switch (action) {
      case ChatRecoveryAction.retry:
      case ChatRecoveryAction.retryAnyway:
      case ChatRecoveryAction.reloadModel:
        await controller.ensureModelLoaded();
      case ChatRecoveryAction.smallerModel:
        final picked = await showModelPickerSheet(
          context,
          selectedModelId: state.modelId,
          smallerModelsOnly: true,
        );
        if (picked != null) await controller.switchModel(picked);
      case ChatRecoveryAction.redownload:
        if (state.model != null && context.mounted) {
          unawaited(
            context.push(
              '/models/repo/${Uri.encodeComponent(state.model!.repoId)}',
            ),
          );
        }
      case ChatRecoveryAction.copyDetails:
        // Model-load failures carry no message id; nothing to copy.
        break;
    }
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    bool markdown,
  ) async {
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    final repo = ref.read(chatRepositoryProvider);
    final content = markdown
        ? await repo.exportConversationMarkdown(conversationId)
        : await repo.exportConversationJson(conversationId);
    await SharePlus.instance.share(
      ShareParams(
        text: content,
        subject: state.title.isEmpty ? 'Dhruva conversation' : state.title,
      ),
    );
  }
}

/// Loop 5, chat-spec.md §1.1's AppBar slot, character variant: replaces the
/// model chip with the character's avatar/name for a character-bound
/// conversation (the persona is still what actually reached the engine —
/// see `ChatController._buildFromCharacter` — this is display only). Tap
/// opens the character's detail screen.
class _CharacterAppBarTitle extends ConsumerWidget {
  final int characterId;
  const _CharacterAppBarTitle({required this.characterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final character = ref.watch(characterInfoProvider(characterId)).value;
    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radius.full),
      onTap: () => context.push('/characters/$characterId'),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              character?.avatarEmoji ?? '⭐',
              style: const TextStyle(fontSize: 16),
            ),
            SizedBox(width: tokens.spacing.xs),
            Text(
              character?.name ?? 'Character',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
