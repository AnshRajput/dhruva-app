/// Chat thread screen (chat-spec.md §1-4, §7-8) — the `/chat/:id` route.
library;

import 'dart:async' show unawaited;
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/device_health/device_guard_policy.dart';
import '../../../core/device_health/device_health_provider.dart';
import '../../../core/di/ask_providers.dart';
import '../../../core/di/library_providers.dart';
import '../../../core/di/model_download.dart';
import '../../../core/di/providers.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/intents/process_text.dart';
import '../../../core/theme/brand_star.dart' show DhruvaLoader;
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../data/chat/chat_repository.dart';
import '../../../data/connectors/ask_sources.dart';
import '../../../data/library/todo_parser.dart';
import '../state/ask_selection.dart';
import '../state/character_info_provider.dart';
import '../state/chat_controller.dart';
import '../state/installed_models_provider.dart';
import '../state/lighter_model.dart';
import '../state/message_info_x.dart';
import '../widgets/answer_source_chips.dart';
import '../widgets/chat_error.dart';
import '../widgets/composer.dart';
import '../widgets/empty_states.dart';
import '../widgets/heat_banner.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_chip.dart';
import '../widgets/model_downloading_view.dart';
import '../widgets/reply_status.dart';
import '../widgets/report_sheet.dart';
import '../widgets/search_in_chips.dart';
import 'model_picker_sheet.dart';
import 'sampling_settings_sheet.dart';
import 'voice_launch.dart';

class ChatThreadScreen extends ConsumerStatefulWidget {
  final ChatRouteArgs args;

  /// Opens hands-free voice once the model is known (Android widget "Talk").
  final bool openVoiceOnStart;
  const ChatThreadScreen({
    super.key,
    required this.args,
    this.openVoiceOnStart = false,
  });

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

    // Opened (Prep / Plan my day) while the first model was still
    // downloading: when the download ends, rebuild the thread so it picks the
    // new model and sends the saved question.
    ref.listen(modelDownloadProvider, (prev, next) {
      if (prev?.value != null &&
          next.value == null &&
          asyncState.value?.model == null) {
        ref.invalidate(provider);
      }
    });

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
          // WS2: a seeded prompt (onboarding "Try asking" chip) auto-sends
          // the first turn — `sendMessage` loads the model itself, so this
          // replaces the plain `ensureModelLoaded` open here rather than
          // racing a second load. Only on an empty draft.
          final seed = widget.args.initialPrompt?.trim();
          if (widget.openVoiceOnStart) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                unawaited(openHandsFreeVoice(context, ref, widget.args));
              }
            });
          } else if (seed != null &&
              seed.isNotEmpty &&
              state.messages.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => controller.sendMessage(seed),
            );
          } else {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => controller.ensureModelLoaded(),
            );
          }
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
      loading: () => const Scaffold(body: Center(child: DhruvaLoader())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(provider),
        ),
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
    final download = state.model == null
        ? ref.watch(modelDownloadProvider).value
        : null;
    final visible = state.visibleMessages;
    // Android text-selection round trip: true when this launch came from an
    // editable field and the result can be handed back.
    final canReplaceSelection = ref.watch(processTextSessionProvider);

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
                loading: state.modelLoading,
                onTap: () => _pickModel(context),
              ),
            ),
          ],
        ),
        titleSpacing: 0,
        actions: [
          if (state.isGenerating)
            TokPerSecTicker(tokPerSec: state.liveTokPerSec),
          // Loop 6, T2/D3: hands-free needs somewhere to send/receive
          // through, same as the composer — gated on a model being picked,
          // same condition the `Composer` below already uses.
          if (state.model != null)
            IconButton(
              // A mic reads as "talk"; the old graphic_eq waveform read as an
              // equalizer and gave no hint this starts a voice conversation.
              icon: const Icon(Icons.record_voice_over_outlined),
              tooltip: 'Talk hands-free',
              onPressed: () => _openHandsFree(context, ref),
            ),
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
                        ? (download != null
                              ? ModelDownloadingView(
                                  progress: download,
                                  pendingPrompt: args.initialPrompt,
                                  onOpenDownloads: () =>
                                      context.push('/models/downloads'),
                                )
                              : NoModelInstalledView(
                                  onBrowseModels: () =>
                                      context.push('/models/hub'),
                                ))
                        : SuggestedPrompts(
                            onSelect: (prompt) {
                              onScrollToBottom();
                              unawaited(
                                _confirmStart(context, ref).then((ok) {
                                  if (ok) {
                                    unawaited(controller.sendMessage(prompt));
                                  }
                                }),
                              );
                            },
                            // Vision is advertised ("analyze photos") but has
                            // no guided path from a loaded text model — surface
                            // one, shaped to whether a vision model is already
                            // installed.
                            isMultimodal: state.isMultimodal,
                            hasVisionModelInstalled:
                                ref
                                    .watch(installedModelsProvider)
                                    .value
                                    ?.any(
                                      (m) => m.isVision && m.mmprojPath != null,
                                    ) ??
                                false,
                            onGetVisionModel: () => context.push('/models/hub'),
                            onSwitchModel: () => _pickModel(context),
                            onOpenWorkflows: () => context.push('/actions'),
                            onOpenConnect: () =>
                                context.push('/settings/connectors'),
                          ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: scrollCtrl,
                        padding: EdgeInsets.all(tokens.spacing.md),
                        itemCount:
                            visible.length +
                            (_warming ? 1 : 0) +
                            (state.modelLoadError != null ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i < visible.length) {
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: tokens.spacing.xs,
                              ),
                              child: _buildMessageItem(
                                context,
                                ref,
                                visible,
                                i,
                                canReplaceSelection: canReplaceSelection,
                              ),
                            );
                          }
                          var index = i - visible.length;
                          if (_warming) {
                            if (index == 0) return _buildWarmUp();
                            index -= 1;
                          }
                          return ChatErrorCard(
                            content: chatErrorContentFor(
                              state.modelLoadError!.runtimeType.toString(),
                              modelSizeBytes: state.model?.sizeBytes,
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
                            // Fade plus an ~8 px rise (fade only when motion is
                            // reduced).
                            child: AnimatedSlide(
                              offset:
                                  pinnedToBottom &&
                                      !MediaQuery.disableAnimationsOf(context)
                                  ? const Offset(0, 0.2)
                                  : Offset.zero,
                              duration: tokens.motion.fast,
                              curve: tokens.motion.standard,
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
                      ),
                    ],
                  ),
          ),
          // The in-thread "Warming up" row covers a send; the bar is only for
          // the screen-open load, before any turn exists.
          if (state.modelLoading && state.warmingSince == null)
            const LinearProgressIndicator(),
          if (state.isGenerating &&
              DeviceGuardPolicy.thermalAction(
                    ref.watch(deviceHealthProvider.select((h) => h.thermal)),
                  ) ==
                  ThermalAction.warn)
            Builder(
              builder: (context) {
                final lighter = lighterModel(
                  ref.watch(installedModelsProvider).value ?? const [],
                  state.model,
                );
                return HeatBanner(
                  onUseLighterModel: lighter == null
                      ? null
                      : () => controller.useLighterModel(lighter),
                );
              },
            ),
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
              isMultimodal: state.isMultimodal,
              documents: state.documents,
              extractingDocName: state.extractingDocName,
              documentError: state.documentError,
              // Ask: "Search in" chips (not for persona/roleplay threads).
              header: state.characterId != null
                  ? null
                  : _SearchInRow(
                      args: args,
                      hasDocuments: state.documents.isNotEmpty,
                    ),
              initialText: args.initialDraft,
              onChanged: (text) =>
                  ref.read(askSelectionProvider(args).notifier).setDraft(text),
              onAttachDocument: controller.attachDocument,
              onRemoveDocument: controller.removeDocument,
              onDismissDocumentError: controller.dismissDocumentError,
              onCancelDocumentRead: controller.cancelDocumentRead,
              beforeSend: () => _confirmStart(context, ref),
              onSend: (text, imageBytes) {
                onScrollToBottom();
                controller.sendMessage(text, imageBytes: imageBytes);
              },
              onCancel: controller.cancel,
              onOpenSettings: () => showSamplingSettingsSheet(context, args),
            ),
        ],
      ),
    );
  }

  bool get _warming => state.warmingSince != null || state.awaitingFirstToken;

  /// The row under the user's message while the reply has not started:
  /// "Warming up (model) · 4 s", or the plain-words timeout card.
  Widget _buildWarmUp() {
    final searching = state.searchingLabel;
    if (searching != null) return SearchingStatus(label: searching);
    final since = state.warmingSince ?? DateTime.now();
    if (state.firstTokenTimedOut) {
      return StalledTurnCard(
        seconds: DateTime.now().difference(since).inSeconds,
        onStop: () => unawaited(controller.cancel()),
        onTryAgain: () => unawaited(controller.retryStalled()),
      );
    }
    return WarmUpStatus(
      modelName: state.model == null
          ? null
          : modelShortLabel(state.model!.repoId),
      loading: state.modelLoading,
      since: since,
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    WidgetRef ref,
    List<MessageInfo> visible,
    int index, {
    bool canReplaceSelection = false,
  }) {
    final message = visible[index];
    if (message.role == MessageRole.assistant &&
        message.status == MessageStatus.error &&
        message.content.trim().isEmpty) {
      return ChatErrorCard(
        content: chatErrorContentFor(
          message.errorKind,
          modelSizeBytes: state.model?.sizeBytes,
        ),
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
    final finishedReply =
        message.role == MessageRole.assistant &&
        !isStreamingMessage &&
        message.status != MessageStatus.error &&
        message.content.trim().isNotEmpty;
    // "Extract to-dos" replies: offer to add the tasks to the Library. A tap,
    // never automatic.
    final todos = finishedReply
        ? parseTodos(message.content)
        : const <String>[];
    final bubble = MessageBubble(
      message: message,
      onSave: finishedReply
          ? () async {
              await ref
                  .read(libraryStoreProvider)
                  .saveAnswer(
                    message.content,
                    conversationId: state.conversationId,
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved to Library.')),
                );
              }
            }
          : null,
      todoCount: todos.length,
      onAddTodos: todos.isEmpty
          ? null
          : () async {
              final added = await ref
                  .read(libraryStoreProvider)
                  .addTodos(todos, conversationId: state.conversationId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      added == 0
                          ? 'Those are already in your to-dos.'
                          : 'Added $added to your to-dos in Library.',
                    ),
                  ),
                );
              }
            },
      isStreaming: isStreamingMessage,
      reasoningDurationMs: state.reasoningDurationMs[message.id],
      reasoningOpen:
          isStreamingMessage &&
          !state.reasoningDurationMs.containsKey(message.id),
      attachedImage: state.attachedImages[message.id],
      onOpenItemSource: (source) => unawaited(_openSource(context, source)),
      onRegenerate: message.role == MessageRole.assistant && canAct
          ? () => unawaited(
              _confirmStart(context, ref).then((ok) {
                if (ok) unawaited(controller.regenerate(message.id));
              }),
            )
          : null,
      onEdit: message.role == MessageRole.user && canAct
          ? () => _editMessage(context, message)
          : null,
      onReport:
          message.role == MessageRole.assistant &&
              !isStreamingMessage &&
              message.status != MessageStatus.error
          ? () => showReportSheet(
              context,
              message: message,
              modelName: state.model?.fileName,
              onReported: () => controller.markReported(message.id),
            )
          : null,
    );
    if (message.role != MessageRole.assistant || isStreamingMessage) {
      return bubble;
    }
    // "Replace selected text": only on the newest finished reply, only when
    // the selection menu came from an editable field, only on the user's tap.
    final end = _replyEnd(message);
    if (canReplaceSelection &&
        canAct &&
        index == visible.length - 1 &&
        end == null &&
        message.content.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bubble,
          Padding(
            padding: EdgeInsets.only(
              bottom: Theme.of(context).extension<DhruvaTokens>()!.spacing.sm,
            ),
            child: FilledButton.icon(
              key: const ValueKey('replace-selected-text'),
              onPressed: () =>
                  unawaited(_replaceSelection(context, ref, message)),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Replace selected text'),
            ),
          ),
        ],
      );
    }
    // D1: a reply that did not finish says why and can be resumed (only the
    // newest reply, and only while nothing else is running).
    if (end == null) return bubble;
    final canContinue = canAct && index == visible.length - 1;
    final empty = message.content.trim().isEmpty;
    final note = ReplyStatusNote(
      end: end,
      onContinue: !canContinue
          ? null
          : empty
          ? () => unawaited(controller.regenerate(message.id))
          : () => unawaited(
              _confirmStart(context, ref).then((ok) {
                if (ok) unawaited(controller.continueMessage(message.id));
              }),
            ),
      actionLabel: empty ? 'Try again' : 'Continue',
    );
    // An empty stopped reply has no text worth a bubble: the note alone.
    if (empty) return note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bubble, note],
    );
  }

  /// A source chip under an answer: loads the live item and shows it. A chip
  /// whose item is gone opens a plain "no longer on this phone" sheet.
  Future<void> _openSource(BuildContext context, ItemSource source) async {
    final item = await controller.loadSourceItem(source);
    if (!context.mounted) return;
    await showSourceSheet(context, source: source, item: item);
  }

  Future<void> _replaceSelection(
    BuildContext context,
    WidgetRef ref,
    MessageInfo message,
  ) async {
    final failure = await ref
        .read(processTextBridgeProvider)
        .returnResult(message.content);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(processTextFailureMessage(failure))),
      );
    }
  }

  ReplyEnd? _replyEnd(MessageInfo m) {
    if (state.heatStoppedMessageIds.contains(m.id)) return ReplyEnd.tooHot;
    return switch (m.status) {
      MessageStatus.cancelled => ReplyEnd.stopped,
      MessageStatus.truncated => ReplyEnd.cutShort,
      MessageStatus.error => ReplyEnd.failed,
      MessageStatus.complete => null,
    };
  }

  /// Battery guard, before a generation starts: a low-battery warning is a
  /// one-time snackbar (non-blocking); critically low asks first. Returns
  /// whether to go ahead.
  Future<bool> _confirmStart(BuildContext context, WidgetRef ref) async {
    final health = ref.read(deviceHealthProvider.notifier);
    final advice = await health.preGenerationAdvice();
    if (!context.mounted) return false;
    final percent = ref.read(deviceHealthProvider).batteryPercent;
    switch (advice) {
      case BatteryAdvice.none:
        return true;
      case BatteryAdvice.warn:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Battery is at $percent%. Replies use a lot of power.',
            ),
          ),
        );
        return true;
      case BatteryAdvice.confirm:
        final go = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Battery is almost empty'),
            content: Text(
              'Your battery is at $percent% and not charging. Generating a '
              'reply could drain it. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        return go == true;
    }
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

  /// Loop 6, T2/D3: hands-free mode (`features/voice/ui/handsfree_screen
  /// .dart`) knows nothing about `ChatController` (ADR-002 — it lives in
  /// `features/voice`, which never imports `features/chat`). This builds
  /// the one closure it needs — "say this, get the reply" — against THIS
  /// screen's own `ChatController`, and hands it to the route as `extra`
  /// (same pattern the model-picker's `extra: modelId` flow already uses in
  /// `app_router.dart`) so `core/router` (the one file allowed to import
  /// both features) can wire it into `HandsFreeScreen` without either
  /// feature importing the other.
  ///
  /// `ChatController.sendMessage` already awaits the full generation
  /// (`_runAssistantTurn`'s `completer.future`) before returning, so by the
  /// time this `await` resolves, [state]'s messages list already carries
  /// the finished reply (or a `MessageStatus.error` row) — no separate
  /// "wait for isGenerating to flip back" dance needed.
  void _openHandsFree(BuildContext context, WidgetRef ref) {
    unawaited(openHandsFreeVoice(context, ref, args));
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
          smallerThanBytes: state.model?.sizeBytes,
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
          smallerThanBytes: state.model?.sizeBytes,
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
    // Loop 7: images are session-only, so hand the export the ids of messages
    // that had an image attached this session — it emits a `[image attached]`
    // marker rather than dropping the context (QA LOW).
    final imageMessageIds = state.attachedImages.keys.toSet();
    final content = markdown
        ? await repo.exportConversationMarkdown(
            conversationId,
            imageMessageIds: imageMessageIds,
          )
        : await repo.exportConversationJson(
            conversationId,
            imageMessageIds: imageMessageIds,
          );
    await SharePlus.instance.share(
      ShareParams(
        text: content,
        subject: state.title.isEmpty
            ? '${AppIdentity.shortName} conversation'
            : state.title,
      ),
    );
  }
}

/// The "Search in" row inside the composer: reads the thread's selection, the
/// connectors' live state and the contact names, and shows what Auto would
/// search for the text typed so far.
class _SearchInRow extends ConsumerWidget {
  final ChatRouteArgs args;
  final bool hasDocuments;
  const _SearchInRow({required this.args, required this.hasDocuments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(askSelectionProvider(args));
    final connectors = ref.watch(askConnectorsProvider);
    final names = ref.watch(askContactNamesProvider).value ?? const [];
    final chips = askChips(connectors: connectors, hasDocuments: hasDocuments);
    final focus = ref.watch(askFocusItemsProvider(args)).value ?? const [];
    // One chip per file, however many sections it was split into.
    final focusTitles = <String>[
      for (final t in {
        for (final i in focus)
          i.title.trim().isEmpty ? i.kind.name : i.title.trim(),
      })
        t,
    ];
    if (chips.isEmpty && focusTitles.isEmpty) return const SizedBox.shrink();
    final ready = {
      for (final c in chips)
        if (c.availability == AskChipAvailability.ready) c.source,
    };
    final resolved = picked.selection
        .resolve(
          question: picked.draft,
          contactNames: names,
          hasDocuments: hasDocuments,
        )
        .intersection(ready);
    final notifier = ref.read(askSelectionProvider(args).notifier);
    return SearchInChips(
      selection: picked.selection,
      focusTitles: focusTitles,
      resolved: resolved,
      chips: chips,
      onAuto: notifier.chooseAuto,
      onToggle: (s) => notifier.toggle(s, currentlyResolved: resolved),
      onConnect: (s) => context.push(connectRouteFor(s)),
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
            _MiniCharacterAvatar(
              avatarEmoji: character?.avatarEmoji,
              avatarPath: character?.avatarPath,
              size: 16,
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

/// Designer BLOCKING #1 (Loop 5 fix pass): the AppBar chip used to render
/// `avatarEmoji ?? '⭐'` as bare `Text`, ignoring `avatarPath` entirely — an
/// image-avatar character showed a generic star instead of their real
/// picture. This mirrors `features/characters/widgets/character_avatar.dart`
/// `CharacterAvatar` exactly (same fallback order: picked image, then emoji,
/// then star) at chip scale — a deliberate small duplicate, not a
/// cross-feature import (ADR-002 bans `features/chat` importing
/// `features/characters`; same precedent as `core/theme/brand_star.dart`'s
/// documented duplication of `DhruvaStar`).
class _MiniCharacterAvatar extends StatelessWidget {
  final String? avatarEmoji;
  final String? avatarPath;
  final double size;

  const _MiniCharacterAvatar({
    this.avatarEmoji,
    this.avatarPath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = avatarPath;
    final hasImage = path != null && File(path).existsSync();
    return Semantics(
      label: 'Character avatar',
      image: true,
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: hasImage
              ? Image.file(
                  File(path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                )
              : Text(
                  avatarEmoji ?? '⭐',
                  style: TextStyle(
                    fontSize: size * 0.85,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}
